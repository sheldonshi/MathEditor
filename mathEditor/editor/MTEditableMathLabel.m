//
//  EditableMathUILabel.m
//
//  Created by Kostub Deshmukh on 9/2/13.
//  Copyright (C) 2013 MathChat
//   
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

#import <QuartzCore/QuartzCore.h>

#import "MTEditableMathLabel.h"
#import "MTMathList.h"
#import "MTMathUILabel.h"
#import "MTMathAtomFactory.h"
#import "MTCaretView.h"
#import "MTMathList+Editing.h"
#import "MTDisplay+Editing.h"

#import "MTUnicode.h"
#import "MTMathListBuilder.h"

@interface MTEditableMathLabel() <UIGestureRecognizerDelegate, UITextInput>

@property (nonatomic) MTMathUILabel* label;
@property (nonatomic) UITapGestureRecognizer* tapGestureRecognizer;

@end

@implementation MTEditableMathLabel {
    MTCaretView* _caretView;
    MTMathListIndex* _insertionIndex;
    CGAffineTransform _flipTransform;
    NSMutableArray* _indicesToHighlight;
    BOOL _showingError;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        [self initialize];
    }
    return self;
}

- (void)awakeFromNib
{
    [self initialize];
}

- (void) createCancelImage
{
    self.cancelImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cross"]];
    CGRect frame = CGRectMake(self.frame.size.width - 55, (self.frame.size.height - 45)/2, 45, 45);
    self.cancelImage.frame = frame;
    [self addSubview:self.cancelImage];
    
    self.cancelImage.userInteractionEnabled = YES;
    UITapGestureRecognizer *cancelRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearTapped:)];
    [self.cancelImage addGestureRecognizer:cancelRecognizer];
    cancelRecognizer.delegate = nil;
    self.cancelImage.hidden = YES;
}

- (void) initialize
{
    // Add tap gesture recognizer to let the user enter editing mode.
    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [self addGestureRecognizer:self.tapGestureRecognizer];
    self.tapGestureRecognizer.delegate = self;
    
    // Create our text storage.
    
    self.mathList =  [MTMathList new];
    
    self.userInteractionEnabled = YES;
    self.autoresizesSubviews = YES;
    
    // Create and set up the APLSimpleCoreTextView that will do the drawing.
    MTMathUILabel *label = [[MTMathUILabel alloc] initWithFrame:self.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:label];
    label.fontSize = 30;
    label.backgroundColor = self.backgroundColor;
    label.userInteractionEnabled = NO;
    label.textAlignment = kMTTextAlignmentCenter;
    self.label = label;
    CGAffineTransform transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height);
    _flipTransform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.0, -1.0), transform);

    _caretView = [[MTCaretView alloc] initWithEditor:self];
    _caretView.caretColor = self.caretColor;

    _indicesToHighlight = [NSMutableArray array];
    _highlightColor = [UIColor colorWithRed:0.8 green:0 blue:0.0 alpha:1.0];
    _textColor = [UIColor blackColor]; // Default text color
    _placeholderColor = _textColor;
    [self bringSubviewToFront:self.cancelImage];
    
    // start with an empty math list
    self.mathList = [MTMathList new];
    
    [self setupErrorLabel];
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    
    CGRect frame = CGRectMake(self.frame.size.width - 55, (self.frame.size.height - 45)/2, 45, 45);
    self.cancelImage.frame = frame;

    self.errorLabel.frame = [self errorLabelFrame];
    
    // update the flip transform
    CGAffineTransform transform = CGAffineTransformMakeTranslation(0, self.bounds.size.height);
    _flipTransform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.0, -1.0), transform);
    
    [self.label layoutIfNeeded];
    [self insertionPointChanged];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    [super setBackgroundColor:backgroundColor];
    self.label.backgroundColor = backgroundColor;
}

- (void)setFontSize:(CGFloat)fontSize
{
    self.label.fontSize = fontSize;
    _caretView.fontSize = fontSize;
    // Update the cursor position when the font size changes.
    [self insertionPointChanged];
}

- (void)setTextColor:(UIColor *)textColor {
    self.label.textColor = textColor;
}

- (void)setPlaceholderColor:(UIColor *)placeholderColor {
    self.label.placeholderColor = placeholderColor;
}

- (void)setTextAlignment:(MTTextAlignment)textAlignment {
    self.label.textAlignment = textAlignment;
}

- (void)setCaretColor:(UIColor *)caretColor {
    _caretView.caretColor = caretColor;
}

- (CGFloat)fontSize
{
    return self.label.fontSize;
}

- (void)setPaddingBottom:(CGFloat)paddingBottom
{
    self.label.paddingBottom = paddingBottom;
}

- (CGFloat)paddingBottom
{
    return self.label.paddingBottom;
}

- (void)setPaddingTop:(CGFloat)paddingTop
{
    self.label.paddingTop = paddingTop;
}

- (CGFloat)paddingTop
{
    return self.label.paddingTop;
}

- (CGSize) mathDisplaySize
{
    return [self.label sizeThatFits:self.label.bounds.size];
}

#pragma mark - Custom user interaction

- (UIView *)inputView
{
    return self.keyboard;
}

- (UIView *)inputAccessoryView
{
    return self.accessoryView;
}

/**
 UIResponder protocol override.
 Our view can become first responder to receive user text input.
 */
- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL canBecome = [super becomeFirstResponder];
    if (canBecome) {
        if (_insertionIndex == nil) {
            _insertionIndex = [MTMathListIndex level0Index:self.mathList.atoms.count];
        }

        [self.keyboard startedEditing:self];
        
        [self insertionPointChanged];
        if ([self.delegate respondsToSelector:@selector(didBeginEditing:)]) {
            [self.delegate didBeginEditing:self];
        }
    } else {
        // Sometimes it takes some time
        // [self performSelector:@selector(startEditing) withObject:nil afterDelay:0.0];
    }
    return canBecome;
}

/**
 UIResponder protocol override.
 Called when our view is being asked to resign first responder state.
 */
- (BOOL)resignFirstResponder
{
    BOOL val = YES;
    if ([self isFirstResponder]) {
        [self.keyboard finishedEditing:self];
         val = [super resignFirstResponder];
        [self insertionPointChanged];
        if ([self.delegate respondsToSelector:@selector(didEndEditing:)]) {
            [self.delegate didEndEditing:self];
        }
    }
    return val;
}

/**
 UIGestureRecognizerDelegate method.
 Called to determine if we want to handle a given gesture.
 */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch
{
	// If gesture touch occurs in our view, we want to handle it
    return YES;
    //return (touch.view == self);
}

- (void) startEditing
{
    #if DEBUG
    NSDate *start = [NSDate date];
    #endif
    
    if (![self isFirstResponder]) {
		// Become first responder state (which shows software keyboard, if applicable).
        [self becomeFirstResponder];
    }
    
    #if DEBUG
    NSDate *methodFinish = [NSDate date];
    NSTimeInterval executionTime = [methodFinish timeIntervalSinceDate:start];
    
    NSLog(@"Execution Time for startEditing: %f", executionTime);
    #endif
}

/**
 Our tap gesture recognizer selector that enters editing mode, or if already in editing mode, updates the text insertion point.
 */
- (void)tap:(UITapGestureRecognizer *)tap
{
    if (![self isFirstResponder]) {
        _insertionIndex = nil;
        [_caretView showHandle:NO];
        [self startEditing];
    } else {
        // If already editing move the cursor and show handle
        _insertionIndex = [self closestIndexToPoint:[tap locationInView:self]];
        if (_insertionIndex == nil) {
            _insertionIndex = [MTMathListIndex level0Index:self.mathList.atoms.count];
        }
        [_caretView showHandle:NO];
        [self insertionPointChanged];
    }
}

- (void)clearTapped:(UITapGestureRecognizer *)tap
{
    [self clear];
}

- (void)clear
{
    self.mathList = [MTMathList new];
    [self insertionPointChanged];
}

- (void)moveCaretToPoint:(CGPoint)point
{
    _insertionIndex = [self closestIndexToPoint:point];
    [_caretView showHandle:NO];
    [self insertionPointChanged];
}

+ (void) clearPlaceholders:(MTMathList*) mathList
{
    for (MTMathAtom* atom in mathList.atoms) {
        if (atom.type == kMTMathAtomPlaceholder) {
            atom.nucleus = MTSymbolWhiteSquare;
        }
        
        if (atom.superScript) {
            [self clearPlaceholders:atom.superScript];
        }
        if (atom.subScript) {
            [self clearPlaceholders:atom.subScript];
        }

        if (atom.type == kMTMathAtomRadical) {
            MTRadical *rad = (MTRadical *) atom;
            [self clearPlaceholders:rad.degree];
            [self clearPlaceholders:rad.radicand];
        }

        if (atom.type == kMTMathAtomFraction) {
            MTFraction* frac = (MTFraction*) atom;
            [self clearPlaceholders:frac.numerator];
            [self clearPlaceholders:frac.denominator];
        }
    }
}
- (void)setMathList:(MTMathList *)mathList
{
    if (mathList) {
        _mathList = mathList;
    } else {
        // clear
        _mathList = [MTMathList new];
    }
    self.label.mathList = self.mathList;
    _insertionIndex = [MTMathListIndex level0Index:mathList.atoms.count];
    [self insertionPointChanged];
}

// Helper method to update caretView when insertion point/selection changes.
- (void) insertionPointChanged
{
	// If not in editing mode, we don't show the caret.
    if (![self isFirstResponder]) {
        [_caretView removeFromSuperview];
        self.cancelImage.hidden = YES;
        return;
    }    
    
    [MTEditableMathLabel clearPlaceholders:self.mathList];
    MTMathAtom* atom = [self.mathList atomAtListIndex:_insertionIndex];
    if (atom.type == kMTMathAtomPlaceholder) {
        atom.nucleus = MTSymbolBlackSquare;
        if (_insertionIndex.finalSubIndexType == kMTSubIndexTypeNucleus) {
            // If the insertion index is inside a placeholder, move it out.
            _insertionIndex = _insertionIndex.levelDown;
        }
        // TODO - disable caret
    } else {
        MTMathListIndex* previousIndex = _insertionIndex.previous;
        atom = [self.mathList atomAtListIndex:previousIndex];
        if (atom.type == kMTMathAtomPlaceholder && atom.superScript == nil && atom.subScript == nil) {
            _insertionIndex = previousIndex;
            atom.nucleus = MTSymbolBlackSquare;
            // TODO - disable caret
        }
    }
    
    [self setKeyboardMode];
    
	/*
     Find the insert point rect and create a caretView to draw the caret at this position.
     */
    
    CGPoint caretPosition = [self caretRectForIndex:_insertionIndex];
    // Check tht we were returned a valid position before displaying a caret there.
    if (CGPointEqualToPoint(caretPosition, CGPointMake(-1, -1))) {
        return;
    }
    
    // caretFrame is in the flipped coordinate system, flip it back
    _caretView.position = CGPointApplyAffineTransform(caretPosition, _flipTransform);
    if (_caretView.superview == nil) {
        [self addSubview:_caretView];
        [self setNeedsDisplay];
    }
    
    // when a caret is displayed, the X symbol should be as well
    self.cancelImage.hidden = NO;
    
    // Set up a timer to "blink" the caret.
    [_caretView delayBlink];
    [self.label setNeedsLayout];
}


- (void) setKeyboardMode
{
    self.keyboard.exponentHighlighted = NO;
    self.keyboard.squareRootHighlighted = NO;
    self.keyboard.radicalHighlighted = NO;
    
    if ([_insertionIndex hasSubIndexOfType:kMTSubIndexTypeSuperscript]) {
        self.keyboard.exponentHighlighted = YES;
        self.keyboard.equalsAllowed = NO;
    }
    if (_insertionIndex.subIndexType == kMTSubIndexTypeNumerator) {
        self.keyboard.equalsAllowed = false;
    } else if (_insertionIndex.subIndexType == kMTSubIndexTypeDenominator) {
        //self.keyboard.fractionsAllowed = false;
        //self.keyboard.equalsAllowed = false;
    }
    
    // handle radicals
    if (_insertionIndex.subIndexType == kMTSubIndexTypeDegree) {
        self.keyboard.radicalHighlighted = YES;
    } else if (_insertionIndex.subIndexType == kMTSubIndexTypeRadicand) {
        self.keyboard.squareRootHighlighted = YES;
    }
}

- (void)insertMathList:(MTMathList *)list atPoint:(CGPoint)point
{
    MTMathListIndex* detailedIndex = [self closestIndexToPoint:point];
    // insert at the given index - but don't consider sublevels at this point
    MTMathListIndex* index = [MTMathListIndex level0Index:detailedIndex.atomIndex];
    for (MTMathAtom* atom in list.atoms) {
        [self.mathList insertAtom:atom atListIndex:index];
        index = index.next;
    }
    self.label.mathList = self.mathList;
    _insertionIndex = index;  // move the index to the end of the new list.
    [self insertionPointChanged];
}

- (void) enableTap:(BOOL) enabled
{
    self.tapGestureRecognizer.enabled = enabled;
}

#pragma mark - Error display

- (void) setupErrorLabel
{
    UILabel *errorLabel = [[UILabel alloc] initWithFrame:[self errorLabelFrame]];
    errorLabel.font = [UIFont systemFontOfSize:17.f];
    errorLabel.backgroundColor = [UIColor colorWithRed:0.969 green:0.282 blue:0.282 alpha:1];
    errorLabel.textColor = [UIColor whiteColor];
    errorLabel.textAlignment = NSTextAlignmentCenter;
    errorLabel.adjustsFontSizeToFitWidth = true;
    errorLabel.minimumFontSize = 12.f;
    errorLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // We do this so the error label is not visible offscreen
    self.layer.masksToBounds = YES;
    [self addSubview:errorLabel];
    
    self.errorLabel = errorLabel;
    
    // Initialize error label variables with default values
    self.autoHidesError = YES;
    self.timeToHideError = 2.0;
    _showingError = NO;
}

- (CGRect) errorLabelFrame
{
    CGFloat errorLabelHeight = 40.f;
    // Show it out of label bounds initially.
    CGFloat errorLabelY = self.bounds.size.height;
    CGRect errorLabelFrame = CGRectMake(0.f, errorLabelY, self.bounds.size.width, errorLabelHeight);
    return errorLabelFrame;
}

- (void) displayError:(NSString*) errorMessage animationDuration:(NSTimeInterval) duration
{
    if (_showingError == YES) {
        return;
    }
    _showingError = YES;
    
    self.errorLabel.text = errorMessage;
    [UIView animateWithDuration:duration animations:^{
        self.errorLabel.frame = CGRectMake(0.0, self.bounds.size.height - self.errorLabel.frame.size.height, self.errorLabel.frame.size.width, self.errorLabel.frame.size.height);
    } completion:^(BOOL finished) {
        if (self.autoHidesError == YES) {
            dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, self.timeToHideError * NSEC_PER_SEC);
            dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
                [self hideError:duration];
            });
        }
    }];
}

- (void) hideError:(NSTimeInterval)duration
{
    if (_showingError == NO) {
        return;
    }
    _showingError = NO;
    
    [UIView animateWithDuration:duration animations:^{
        self.errorLabel.frame = CGRectMake(0.0, self.bounds.size.height, self.errorLabel.frame.size.width, self.errorLabel.frame.size.height);
    }];
}

#pragma mark - UIKeyInput

- (MTMathAtom*) atomForCharacter:(unichar) ch
{
    NSString *chStr = [NSString stringWithCharacters:&ch length:1];
    
    // Ensure all symbols are included
    
    if ([chStr isEqualToString:MTSymbolMultiplication]) {
        return [MTMathAtomFactory times];
    } else if ([chStr isEqualToString:MTSymbolSquareRoot]) {
        return [MTMathAtomFactory placeholderSquareRoot];
    } else if ([chStr isEqualToString:MTSymbolInfinity]) {
        return [MTMathAtom atomWithType:kMTMathAtomOrdinary value:chStr];
    } else if ([chStr isEqualToString:MTSymbolDegree]) {
        return [MTMathAtom atomWithType:kMTMathAtomOrdinary value:chStr];
    } else if ([chStr isEqualToString:MTSymbolAngle]) {
        return [MTMathAtom atomWithType:kMTMathAtomOrdinary value:chStr];
    } else if ([chStr isEqualToString:MTSymbolDivision]) {
        return [MTMathAtomFactory divide];
    } else if ([chStr isEqualToString:MTSymbolFractionSlash]) {
        return [MTMathAtomFactory placeholderFraction];
    } else if (ch == '(' || ch == '[' || ch == '{') {
        return [MTMathAtom atomWithType:kMTMathAtomOpen value:chStr];
    } else if (ch == ')' || ch == ']' || ch == '}') {
        return [MTMathAtom atomWithType:kMTMathAtomClose value:chStr];
    } else if (ch == ',' || ch == ';') {
        return [MTMathAtom atomWithType:kMTMathAtomPunctuation value:chStr];
    } else if (ch == '=' || ch == '<' || ch == '>' || ch == ':' || [chStr isEqualToString:MTSymbolGreaterEqual] || [chStr isEqualToString:MTSymbolLessEqual] || [chStr isEqualToString:MTSymbolNotEqual]) {
        return [MTMathAtom atomWithType:kMTMathAtomRelation value:chStr];
    } else if (ch == '+' || ch == '-') {
        return [MTMathAtom atomWithType:kMTMathAtomBinaryOperator value:chStr];
    } else if (ch == '*') {
        return [MTMathAtomFactory times];
    } else if (ch == '/') {
        return [MTMathAtomFactory divide];
    } else if ([self isNumeric:ch]) {
        return [MTMathAtom atomWithType:kMTMathAtomNumber value:chStr];
    } else if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        return [MTMathAtom atomWithType:kMTMathAtomVariable value:chStr];
    } else if (ch >= kMTUnicodeGreekStart && ch <= kMTUnicodeGreekEnd) {
        // All greek chars are rendered as variables.
        return [MTMathAtom atomWithType:kMTMathAtomVariable value:chStr];
    } else if (ch >= kMTUnicodeCapitalGreekStart && ch <= kMTUnicodeCapitalGreekEnd) {
        // Including capital greek chars
        return [MTMathAtom atomWithType:kMTMathAtomVariable value:chStr];
    } else if (ch < 0x21 || ch > 0x7E || ch == '\'' || ch == '~') {
        // not ascii
        return nil;
    } else {
        // just an ordinary character
        return [MTMathAtom atomWithType:kMTMathAtomOrdinary value:chStr];
    }
}

- (BOOL) isNumeric:(unichar) ch
{
    return ch == '.' || (ch >= '0' && ch <= '9');
}

- (void) handleExponentButton
{
    if ([_insertionIndex hasSubIndexOfType:kMTSubIndexTypeSuperscript]) {
        // The index is currently inside an exponent. The exponent button gets it out of the exponent and move forward.
        _insertionIndex = [self getIndexAfterSpecialStructure:_insertionIndex type:kMTSubIndexTypeSuperscript];
    } else {
        // not in an exponent. Add one.
        if (!_insertionIndex.isAtBeginningOfLine) {
            MTMathAtom* atom = [self.mathList atomAtListIndex:_insertionIndex.previous];
            if (!atom.superScript) {
                atom.superScript = [MTMathList new];
                [atom.superScript addAtom:[MTMathAtomFactory placeholder]];
                _insertionIndex = [_insertionIndex.previous levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeSuperscript];
            } else if (_insertionIndex.finalSubIndexType == kMTSubIndexTypeNucleus) {
                // If we are already inside the nucleus, then we come out and go up to the superscript
                _insertionIndex = [_insertionIndex.levelDown levelUpWithSubIndex:[MTMathListIndex level0Index:atom.superScript.atoms.count] type:kMTSubIndexTypeSuperscript];
            } else {
                _insertionIndex = [_insertionIndex.previous levelUpWithSubIndex:[MTMathListIndex level0Index:atom.superScript.atoms.count] type:kMTSubIndexTypeSuperscript];
            }
        } else {
            // Create an empty atom and move the insertion index up.
            MTMathAtom* emptyAtom = [MTMathAtomFactory placeholder];
            emptyAtom.superScript = [MTMathList new];
            [emptyAtom.superScript addAtom:[MTMathAtomFactory placeholder]];
            
            if (![self updatePlaceholderIfPresent:emptyAtom]) {
                // If the placeholder hasn't been updated then insert it.
                [self.mathList insertAtom:emptyAtom atListIndex:_insertionIndex];
            }
            _insertionIndex = [_insertionIndex levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeSuperscript];
        }
    }
}

- (void) handleSubscriptButton
{
    if ([_insertionIndex hasSubIndexOfType:kMTSubIndexTypeSubscript]) {
        // The index is currently inside an subscript. The subscript button gets it out of the subscript and move forward.
        _insertionIndex = [self getIndexAfterSpecialStructure:_insertionIndex type:kMTSubIndexTypeSubscript];
    } else {
        // not in a subscript. Add one.
        if (!_insertionIndex.isAtBeginningOfLine) {
            MTMathAtom* atom = [self.mathList atomAtListIndex:_insertionIndex.previous];
            if (!atom.subScript) {
                atom.subScript = [MTMathList new];
                [atom.subScript addAtom:[MTMathAtomFactory placeholder]];
                _insertionIndex = [_insertionIndex.previous levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeSubscript];
            } else if (_insertionIndex.finalSubIndexType == kMTSubIndexTypeNucleus) {
                // If we are already inside the nucleus, then we come out and go up to the subscript
                _insertionIndex = [_insertionIndex.levelDown levelUpWithSubIndex:[MTMathListIndex level0Index:atom.subScript.atoms.count] type:kMTSubIndexTypeSubscript];
            } else {
                _insertionIndex = [_insertionIndex.previous levelUpWithSubIndex:[MTMathListIndex level0Index:atom.subScript.atoms.count] type:kMTSubIndexTypeSubscript];
            }
        } else {
            // Create an empty atom and move the insertion index up.
            MTMathAtom* emptyAtom = [MTMathAtomFactory placeholder];
            emptyAtom.subScript = [MTMathList new];
            [emptyAtom.subScript addAtom:[MTMathAtomFactory placeholder]];
            
            if (![self updatePlaceholderIfPresent:emptyAtom]) {
                // If the placeholder hasn't been updated then insert it.
                [self.mathList insertAtom:emptyAtom atListIndex:_insertionIndex];
            }
            _insertionIndex = [_insertionIndex levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeSubscript];
        }
    }
}

// If the index is in a radical, subscript, or exponent, fetches the next index after the root atom.
- (MTMathListIndex *) getIndexAfterSpecialStructure:(MTMathListIndex *) index type:(MTMathListSubIndexType)type
{
    MTMathListIndex *nextIndex = index;
    while ([nextIndex hasSubIndexOfType:type]){
        nextIndex = nextIndex.levelDown;
    }

    //Point to just after this node.
    return nextIndex.next;
}

- (void) handleSlashButton
{
    // special / handling - makes the thing a fraction
    MTMathList* numerator = [MTMathList new];
    MTMathListIndex* current = _insertionIndex;
    for (; !current.isAtBeginningOfLine; current = current.previous) {
        MTMathAtom* atom = [self.mathList atomAtListIndex:current.previous];
        if (atom.type != kMTMathAtomNumber && atom.type != kMTMathAtomVariable) {
            // we don't put this atom on the fraction
            break;
        } else {
            // add the number to the beginning of the list
            [numerator insertAtom:atom atIndex:0];
        }
    }
    if (current.atomIndex == _insertionIndex.atomIndex) {
        // so we didn't really find any numbers before this, so make the numerator 1
        [numerator addAtom:[self atomForCharacter:'1']];
        if (!current.isAtBeginningOfLine) {
            MTMathAtom* prevAtom = [self.mathList atomAtListIndex:current.previous];
            if (prevAtom.type == kMTMathAtomFraction) {
                // add a times symbol
                [self.mathList insertAtom:[MTMathAtomFactory times] atListIndex:current];
                current = current.next;
            }
        }
    } else {
        // delete stuff in the mathlist from current to _insertionIndex
        [self.mathList removeAtomsInListIndexRange:[MTMathListRange makeRange:current length:_insertionIndex.atomIndex - current.atomIndex]];
    }
    
    // create the fraction
    MTFraction *frac = [MTFraction new];
    frac.denominator = [MTMathList new];
    [frac.denominator addAtom:[MTMathAtomFactory placeholder]];
    frac.numerator = numerator;
    
    // insert it
    [self.mathList insertAtom:frac atListIndex:current];
    // update the insertion index to go the denominator
    _insertionIndex = [current levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeDenominator];
}

- (MTMathListIndex *) getOutOfRadical:(MTMathListIndex *)index {
    if ([index hasSubIndexOfType:kMTSubIndexTypeDegree]) {
        index = [self getIndexAfterSpecialStructure:index type:kMTSubIndexTypeDegree];
    }
    if ([index hasSubIndexOfType:kMTSubIndexTypeRadicand]) {
        index = [self getIndexAfterSpecialStructure:index type:kMTSubIndexTypeRadicand];
    }
    return index;
}

- (void)handleRadical:(BOOL)withDegreeButtonPressed {
    MTRadical *rad;
    MTMathListIndex *current = _insertionIndex;

    if ([current hasSubIndexOfType:kMTSubIndexTypeDegree] || [current hasSubIndexOfType:kMTSubIndexTypeRadicand]) {
        rad = self.mathList.atoms[current.atomIndex];
        if (withDegreeButtonPressed) {
            if (!rad.degree) {
                rad.degree = [MTMathList new];
                [rad.degree addAtom:[MTMathAtomFactory placeholder]];
                _insertionIndex = [[current levelDown] levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeDegree];
            } else {
                // The radical the cursor is at has a degree. If the cursor is in the radicand, move the cursor to the degree
                if ([current hasSubIndexOfType:kMTSubIndexTypeRadicand]) {
                    // If the cursor is at the radicand, switch it to the degree
                    _insertionIndex = [[current levelDown] levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeDegree];
                } else {
                    // If the cursor is at the degree, get out of the radical
                    _insertionIndex = [self getOutOfRadical:current];
                }
            }
        } else {
            if ([current hasSubIndexOfType:kMTSubIndexTypeDegree]) {
                // If the radical the cursor at has a degree, and the cursor is at the degree, move the cursor to the radicand.
                _insertionIndex = [[current levelDown] levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeRadicand];
            } else {
                // If the cursor is at the radicand, get out of the radical.
                _insertionIndex = [self getOutOfRadical:current];
            }
        }
    } else {
        if (withDegreeButtonPressed) {
            rad = [MTMathAtomFactory placeholderRadical];

            [self.mathList insertAtom:rad atListIndex:current];
            _insertionIndex = [current levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeDegree];
        } else {
            rad = [MTMathAtomFactory placeholderSquareRoot];

            [self.mathList insertAtom:rad atListIndex:current];
            _insertionIndex = [current levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeRadicand];
        }

    }
}

- (void) removePlaceholderIfPresent
{
    MTMathAtom* current = [self.mathList atomAtListIndex:_insertionIndex];
    if (current.type == kMTMathAtomPlaceholder) {
        // remove this element - the inserted text replaces the placeholder
        [self.mathList removeAtomAtListIndex:_insertionIndex];
    }
}

// Returns true if updated
- (BOOL) updatePlaceholderIfPresent:(MTMathAtom*) atom
{
    MTMathAtom* current = [self.mathList atomAtListIndex:_insertionIndex];
    if (current.type == kMTMathAtomPlaceholder) {
        if (current.superScript) {
            atom.superScript = current.superScript;
        }
        if (current.subScript) {
            atom.subScript = current.subScript;
        }
        // remove the placeholder and replace with atom.
        [self.mathList removeAtomAtListIndex:_insertionIndex];
        [self.mathList insertAtom:atom atListIndex:_insertionIndex];
        return YES;
    }
    return NO;
}

- (void) insertText:(NSString*) str
{
//    if ([str isEqualToString:@"\n"]) {
//        if ([self.delegate respondsToSelector:@selector(returnPressed:)]) {
//            [self.delegate returnPressed:self];
//        }
//        return;
//    }

    if (str.length == 0) {
        NSLog(@"Encounter key with 0 length string: %@", str);
        return;
    }

    unichar ch = [str characterAtIndex:0];
    MTMathAtom* atom;
    if (str.length > 1) {
        // Check if this is a supported command
        NSDictionary* commands = [MTMathAtomFactory supportedLatexSymbolNames];
        MTMathAtom* factoryAtom = commands[str];
        atom = [factoryAtom copy]; // Make a copy here since atoms are mutable and we don't want to update the atoms in the map.
    } else {
        atom = [self atomForCharacter:ch];
    }

    if (_insertionIndex.subIndexType == kMTSubIndexTypeDenominator) {
        if (atom.type == kMTMathAtomRelation) {
            // pull the insertion index out
            _insertionIndex = [[_insertionIndex levelDown] next];
        }
    }

    if (ch == '^') {
        // Special ^ handling - adds an exponent
        [self handleExponentButton];
    } else if ([str isEqualToString:MTSymbolSquareRoot]) {
        [self handleRadical:NO];
    } else if ([str isEqualToString:MTSymbolCubeRoot]) {
        [self handleRadical:YES];
    } else if (ch == '_') {
        [self handleSubscriptButton];
    } else if (ch == '/') {
        [self handleSlashButton];
    } else if ([str isEqualToString:@"()"]) {
        [self removePlaceholderIfPresent];
        [self insertParens];
    } else if ([str isEqualToString:@"||"]) {
        [self removePlaceholderIfPresent];
        [self insertAbsValue];
    } else if ([str isEqualToString:@"\n"]) {
        [self removePlaceholderIfPresent];
        [self insertNewLine];
    } else if (atom) {
        if (![self updatePlaceholderIfPresent:atom]) {
            // If a placeholder wasn't updated then insert the new element.
            [self.mathList insertAtom:atom atListIndex:_insertionIndex];
        }
        if (atom.type == kMTMathAtomFraction) {
            // go to the numerator
            _insertionIndex = [_insertionIndex levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeNumerator];
        } else {
            _insertionIndex = _insertionIndex.next;
        }
    }

    self.label.mathList = self.mathList;
    [self insertionPointChanged];

    // If trig function, insert parens after
    if ([self isTrigFunction:str]) {
        [self insertParens];
    }

    if ([self.delegate respondsToSelector:@selector(textModified:)]) {
        [self.delegate textModified:self];
    }
}

// Return YES if string is a trig function, otherwise return NO
- (BOOL)isTrigFunction:(NSString *)string {
    NSArray *trigFunctions = @[@"sin", @"cos", @"tan", @"sec", @"csc", @"cot"];

    for (NSString *trigFunction in trigFunctions) {
        if ([string isEqualToString:trigFunction]) {
            return YES;
        }
    }

    return NO;
}

- (void) insertNewLine
{
    MTMathTable* mathTable = [[MTMathTable alloc] initWithEnvironment:nil];
    [mathTable setAlignment:kMTColumnAlignmentLeft forColumn:0];
    [mathTable setCell:self.mathList forRow:0 column:0];
    
    MTMathList* secondRow = [MTMathList new];
    [secondRow addAtom:[MTMathAtomFactory placeholder]];
    [mathTable setCell:secondRow forRow:1 column:0];
    
    MTMathList *newMathList = [MTMathList new];
    [newMathList addAtom:mathTable];
    
    self.mathList = newMathList;
}

- (void) insertParens
{
    char ch = '(';
    MTMathAtom* atom = [self atomForCharacter:ch];
    [self.mathList insertAtom:atom atListIndex:_insertionIndex];
    _insertionIndex = _insertionIndex.next;
    ch = ')';
    atom = [self atomForCharacter:ch];
    [self.mathList insertAtom:atom atListIndex:_insertionIndex];
    // Don't go to the next insertion index, to start inserting before the close parens.
}

- (void) insertAbsValue
{
    char ch = '|';
    MTMathAtom* atom = [self atomForCharacter:ch];
    [self.mathList insertAtom:atom atListIndex:_insertionIndex];
    _insertionIndex = _insertionIndex.next;
    [self.mathList insertAtom:[MTMathAtomFactory placeholder] atListIndex:_insertionIndex];
    _insertionIndex = _insertionIndex.next;
    atom = [self atomForCharacter:ch];
    [self.mathList insertAtom:atom atListIndex:_insertionIndex];
    // Don't go to the next insertion index, to start inserting before the second absolute value
}

- (void) deleteBackward
{    
    // Adjust insertion point based on the previous index.
    [self adjustInsertionIndexBasedOnPreviousIndex];
    
    MTMathListIndex* prevIndex = _insertionIndex.previous;
    
    // delete the last atom from the list
    if (self.hasText && prevIndex) {
        [self.mathList removeAtomAtListIndex:prevIndex];
        if (prevIndex.finalSubIndexType == kMTSubIndexTypeNucleus) {
            // it was in the nucleus and we removed it, get out of the nucleus and get in the nucleus of the previous one.
            MTMathListIndex* downIndex = prevIndex.levelDown;
            if (downIndex.previous) {
                prevIndex = [downIndex.previous levelUpWithSubIndex:[MTMathListIndex level0Index:1] type:kMTSubIndexTypeNucleus];
            } else {
                prevIndex = downIndex;
            }
        }
        _insertionIndex = prevIndex;

        [self postDeletionCommon];
        
    } else if (self.hasText && [_insertionIndex isAtBeginningOfLine] == YES && (_insertionIndex.finalSubIndexType == kMTSubIndexTypeSuperscript || _insertionIndex.finalSubIndexType == kMTSubIndexTypeSubscript)) {
        // Handle beginning of line at superscript or subscript
        
        // We are at the beginning of a line in super/subscript. Remove the placeholder
        [self.mathList removeAtomAtListIndex:_insertionIndex];
        
        // We step down one level from the superscript to lower level
        MTMathListIndex* downIndex = _insertionIndex.levelDown;
        MTMathAtom *atomAtDownIndex = [self.mathList atomAtListIndex:downIndex];
        
        // Modify the atom at the lower level so it no longer has a superscript or subscript
        if (atomAtDownIndex != nil) {
            if (_insertionIndex.finalSubIndexType == kMTSubIndexTypeSuperscript) {
                // Remove the superscript
                atomAtDownIndex.superScript = nil;
            }
            if (_insertionIndex.finalSubIndexType == kMTSubIndexTypeSubscript) {
                // Remove the entire fraction
                atomAtDownIndex.subScript = nil;
            }
        }
        
        
        if ([self.mathList atomAtListIndex:downIndex] != nil) {
            // Advance the insertion index one so we go to the end of the lower level's atom
            _insertionIndex = downIndex.next;
        } else {
            // If there is no atom at the lower level, just remain.
            _insertionIndex = downIndex;
        }
        
        [self postDeletionCommon];
    } else if (self.hasText && [_insertionIndex isAtBeginningOfLine] == YES && _insertionIndex.finalSubIndexType == kMTSubIndexTypeRadicand) {
        // Handle the middle of a radical. You can think of the degree subindex as an extension of the middle of the radicand.
        // So if we remove from the beginning of a radicand, the cursor should move to the degree. If there is no degree, just remove the radical.
        
        MTMathListIndex* downIndex = _insertionIndex.levelDown;
        
        // Handle the degree case
        MTMathListIndex* degreeIndex = [downIndex levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeDegree];
        MTMathAtom* degreeAtom = [self.mathList atomAtListIndex:degreeIndex];
        if (degreeAtom != nil) {
            _insertionIndex = [self getLastAtomInLevel:degreeIndex];
            [self postDeletionCommon];
            if (degreeAtom.type != kMTMathAtomPlaceholder) {
                [self deleteBackward];
            }
            return;
        }
        
        // Handle no degree case. Remove the radical
        // Remove placeholder first
        [self.mathList removeAtomAtListIndex:_insertionIndex];
        
        // We step down one level from the radicand to lower level
        MTMathAtom* atomAtDownIndex = [self.mathList atomAtListIndex:downIndex];
        [self.mathList removeAtomAtListIndex:downIndex];
        
        _insertionIndex = downIndex;
        [self postDeletionCommon];
    } else if (self.hasText && [_insertionIndex isAtBeginningOfLine] == YES && (_insertionIndex.finalSubIndexType == kMTSubIndexTypeDegree || _insertionIndex.finalSubIndexType == kMTSubIndexTypeNumerator)) {
        // Degree and Numerator cases are similar to sub/superscripts. Go down a level, and remove the atom there. Basically, if we're in degree and numerator cases at the beginning of a line, remove the radical or fraction.
        
        MTMathListIndex* downIndex = _insertionIndex.levelDown;
        
        [self.mathList removeAtomAtListIndex:_insertionIndex];
        
        // We step down one level from the degree to lower level
        MTMathAtom* atomAtDownIndex = [self.mathList atomAtListIndex:downIndex];
        
        // This should never be the case, but let's be safe just in case
        if (atomAtDownIndex != nil) {
            [self.mathList removeAtomAtListIndex:downIndex];
        }
        
        _insertionIndex = downIndex;
        [self postDeletionCommon];
    } else if (self.hasText && [_insertionIndex isAtBeginningOfLine] == YES && _insertionIndex.finalSubIndexType == kMTSubIndexTypeDenominator) {
        // The case of a denominator is similar to the relationship between radicand and degree. If we delete from the beginning of a denominator, move up to the numerator and remove last thing there. If there is only a placeholder there, just move to the numerator without removing anything.
        
        MTMathListIndex* downIndex = _insertionIndex.levelDown;
        MTMathListIndex* numeratorIndex = [downIndex levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:kMTSubIndexTypeNumerator];
        MTMathAtom* atomAtNumeratorIndex = [self.mathList atomAtListIndex:numeratorIndex];
        if (atomAtNumeratorIndex != nil) {
            _insertionIndex = [self getLastAtomInLevel:numeratorIndex];
            [self postDeletionCommon];
            if (atomAtNumeratorIndex.type != kMTMathAtomPlaceholder) {
                [self deleteBackward];
            }
        }
    }
}

/**
    Adjust `_insertionIndex` based on the previous index on the same level. This is important in the cases where user's cursor is right after a complex atom like radical, subscript, superscript, etc.
    We move in the order specified by `subIndexTypesInOrder`. For example, if the user has a cursor after ( (6/5)^2[CURSOR] ), after hitting delete we will delete from superscript. Denominator would be next, then numerator.
 
    This function is only significant if dealing an atom on the same level as `_insertiongIndex`. If we are at the beginning of a level, we need special behavior specified by the different `if` blocks in `deleteBackward`.
 */
- (void) adjustInsertionIndexBasedOnPreviousIndex
{
    MTMathListIndex* prevIndex = _insertionIndex.previous;
    if (prevIndex == nil) {
        return;
    }
    
    // This order is significant. Do not alter it without changing behavior of deletion.
    NSArray *subIndexTypesInOrder = @[
        [NSNumber numberWithInt:kMTSubIndexTypeSubscript],
        [NSNumber numberWithInt:kMTSubIndexTypeSuperscript],
        [NSNumber numberWithInt:kMTSubIndexTypeRadicand],
        [NSNumber numberWithInt:kMTSubIndexTypeDegree],
        [NSNumber numberWithInt:kMTSubIndexTypeDenominator],
        [NSNumber numberWithInt:kMTSubIndexTypeNumerator]];
    
    for (NSNumber *subIndexType in subIndexTypesInOrder) {
        
        MTMathListIndex* levelUpIndex = [prevIndex levelUpWithSubIndex:[MTMathListIndex level0Index:0] type:(MTMathListSubIndexType)subIndexType.intValue];
        MTMathAtom* atom = [self.mathList atomAtListIndex:levelUpIndex];
        
        if (atom != nil) {
            _insertionIndex = [self getLastAtomInLevel:levelUpIndex];
            [self adjustInsertionIndexBasedOnPreviousIndex];
            break;
        }
    }
    
    return;
}

/**
    Get last atom on the same level as `startingIndex`.
 */
- (MTMathListIndex*) getLastAtomInLevel:(MTMathListIndex*) startingIndex
{
    MTMathListIndex* nextIndex = startingIndex.next;
    MTMathAtom* nextAtom = [self.mathList atomAtListIndex:startingIndex];
    while (nextAtom != nil) {
        nextAtom = [self.mathList atomAtListIndex:nextIndex];
        if (nextAtom != nil) {
            nextIndex = nextIndex.next;
        }
    }
    
    return nextIndex;
}

/**
    Perform common tasks post character deletion.
 */
- (void) postDeletionCommon
{
    if (_insertionIndex.isAtBeginningOfLine && _insertionIndex.subIndexType != kMTSubIndexTypeNone) {
        // We have deleted to the beginning of the line and it is not the outermost line
        MTMathAtom* atom = [self.mathList atomAtListIndex:_insertionIndex];
        if (!atom) {
            // add a placeholder if we deleted everything in the list
            atom = [MTMathAtomFactory placeholder];
            // mark the placeholder as selected since that is the current insertion point.
            atom.nucleus = MTSymbolBlackSquare;
            [self.mathList insertAtom:atom atListIndex:_insertionIndex];
        }
    }
    
    self.label.mathList = self.mathList;
    [self insertionPointChanged];
    if ([self.delegate respondsToSelector:@selector(textModified:)]) {
        [self.delegate textModified:self];
    }
}

- (BOOL)hasText
{
    if (self.mathList.atoms.count > 0) {
        return YES;
    }
    return NO;
}

/**
    mathListWithRemovedPlaceholders will remove placeholders from provided `mathList`. For atoms like fractions, radicals, and inner lists we will remove the atom if one of its sublists still has a placeholder, making it invalid. The exception is a radical with a placeholder in its degree list, which will still render correctly with the degree
 */
+ (MTMathList *) mathListWithRemovedPlaceholders:(MTMathList *)mathList
{
    MTMathList *newMathList = [MTMathList new];
    for (MTMathAtom* atom in mathList.atoms) {
        MTMathAtom *atomCopy = [atom copy];
        if (atom.type == kMTMathAtomPlaceholder) {
            continue;
        }
        
        if (atom.superScript) {
            MTMathList *superScript = [self mathListWithRemovedPlaceholders:atomCopy.superScript];
            if (superScript.atoms.count > 0) {
                atomCopy.superScript = superScript;
            } else {
                atomCopy.superScript = nil;
            }
        }
        if (atom.subScript) {
            MTMathList *subScript = [self mathListWithRemovedPlaceholders:atomCopy.subScript];
            if (subScript.atoms.count > 0) {
                atomCopy.subScript = subScript;
            } else {
                atomCopy.subScript = nil;
            }
        }
        
        
        if (atom.type == kMTMathAtomRadical) {
            MTRadical *rad = (MTRadical *)atomCopy;
            
            MTMathList *degree = [self mathListWithRemovedPlaceholders:rad.degree];
            if (degree.atoms.count > 0) {
                rad.degree = degree;
            } else {
                rad.degree = nil;
            }
            
            MTMathList *radicand = [self mathListWithRemovedPlaceholders:rad.radicand];
            if (radicand.atoms.count == 0) {
                continue;
            }
            
            rad.radicand = radicand;
            [newMathList addAtom:rad];
        } else if (atom.type == kMTMathAtomFraction) {
            MTFraction* frac = (MTFraction*)atomCopy;
            MTMathList *numerator = [self mathListWithRemovedPlaceholders:frac.numerator];
            MTMathList *denominator = [self mathListWithRemovedPlaceholders:frac.denominator];
            
            if (numerator.atoms.count == 0 || denominator.atoms.count == 0) {
                continue;
            }
            
            frac.numerator = numerator;
            frac.denominator = denominator;
            [newMathList addAtom:frac];
        } else if (atom.type == kMTMathAtomInner) {
            MTInner* innerAtom = (MTInner *)atomCopy;
            MTMathList *inner = [self mathListWithRemovedPlaceholders:innerAtom.innerList];
            
            if (inner.atoms.count == 0) {
                continue;
            }
            
            innerAtom.innerList = inner;
            [newMathList addAtom:innerAtom];
        } else {
            [newMathList addAtom:atomCopy];
        }
    }
    
    return newMathList;
}

/**
    hasPlaceholders will determine if provided `mathList` has placeholders. It is not greedy, meaning it will return as soon as it finds a placeholder.
 */
+ (BOOL) hasPlaceholders:(MTMathList *)mathList
{
    BOOL foundPlaceholder = NO;
    for (MTMathAtom* atom in mathList.atoms) {
        if (atom.type == kMTMathAtomPlaceholder) {
            return YES;
        }
        
        if (atom.superScript) {
            foundPlaceholder = [self hasPlaceholders:atom.superScript];
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
        }
        
        if (atom.subScript) {
            foundPlaceholder = [self hasPlaceholders:atom.subScript];
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
        }
        
        if (atom.type == kMTMathAtomRadical) {
            MTRadical *rad = (MTRadical *)atom;
            
            foundPlaceholder = [self hasPlaceholders:rad.degree];
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
            
            foundPlaceholder = [self hasPlaceholders:rad.radicand];
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
        } else if (atom.type == kMTMathAtomFraction) {
            MTFraction* frac = (MTFraction*)atom;
            foundPlaceholder = [self hasPlaceholders:frac.numerator];
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
            
            foundPlaceholder = [self hasPlaceholders:frac.denominator];
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
        } else if (atom.type == kMTMathAtomInner) {
            MTInner* innerAtom = (MTInner *)atom;
            foundPlaceholder = [self hasPlaceholders:innerAtom.innerList];
            
            if (foundPlaceholder == YES) {
                return foundPlaceholder;
            }
        }
    }
    return foundPlaceholder;
}

#pragma mark - UITextInputTraits

- (UITextAutocapitalizationType)autocapitalizationType
{
    return UITextAutocapitalizationTypeNone;
}

- (UITextAutocorrectionType)autocorrectionType
{
    return UITextAutocorrectionTypeNo;
}

- (UIReturnKeyType)returnKeyType
{
    return UIReturnKeyDefault;
}

- (UITextSpellCheckingType)spellCheckingType
{
    return UITextSpellCheckingTypeNo;
}

- (UIKeyboardType)keyboardType
{
    return UIKeyboardTypeASCIICapable;
}


#pragma mark - Hit Testing

- (MTMathListIndex *)closestIndexToPoint:(CGPoint)point
{
    [self.label layoutIfNeeded];
    if (!self.label.displayList) {
        // no mathlist, so can't figure it out.
        return nil;
    }
    
    return [self.label.displayList closestIndexToPoint:[self convertPoint:point toView:self.label]];
}

- (CGPoint)caretRectForIndex:(MTMathListIndex *)index
{
    [self.label layoutIfNeeded];
    if (!self.label.displayList) {
        // no mathlist so we can't figure it out.
        return CGPointZero;
    }
    return [self.label.displayList caretPositionForIndex:index];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    BOOL inside = [super pointInside:point withEvent:event];
    if (inside) {
        return YES;
    }
    // check if a point is in the caret view.
    return [_caretView pointInside:[self convertPoint:point toView:_caretView] withEvent:event];
}

#pragma mark - Highlighting

- (void)highlightCharacterAtIndex:(MTMathListIndex *)index
{
    [self.label layoutIfNeeded];
    if (!self.label.displayList) {
        // no mathlist so we can't figure it out.
        return;
    }
    // setup highlights before drawing the MTLine
    
    [self.label.displayList highlightCharacterAtIndex:index color:_highlightColor];
    
    [self.label setNeedsDisplay];
}

- (void) clearHighlights
{
    // relayout the displaylist to clear highlights
    [self.label setNeedsLayout];
}

#pragma mark - UITextInput

// These are blank just to get a UITextInput implementation, to fix the dictation button bug.
// Proposed fix from: http://stackoverflow.com/questions/20980898/work-around-for-dictation-custom-text-view-bug

@synthesize beginningOfDocument;
@synthesize endOfDocument;
@synthesize inputDelegate;
@synthesize markedTextRange;
@synthesize markedTextStyle;
@synthesize selectedTextRange;
@synthesize tokenizer;

- (UITextWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction
{
    return UITextWritingDirectionLeftToRight;
}

- (CGRect)caretRectForPosition:(UITextPosition *)position
{
    return CGRectZero;
}

- (void)unmarkText
{
    
}

- (UITextRange *)characterRangeAtPoint:(CGPoint)point
{
    return nil;
}
- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction
{
    return nil;
}
- (UITextPosition *)closestPositionToPoint:(CGPoint)point
{
    return nil;
}
- (UITextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(UITextRange *)range
{
    return nil;
}
- (NSComparisonResult)comparePosition:(UITextPosition *)position toPosition:(UITextPosition *)other
{
    return NSOrderedSame;
}
- (void)dictationRecognitionFailed
{
}
- (void)dictationRecordingDidEnd
{
}
- (CGRect)firstRectForRange:(UITextRange *)range
{
    return CGRectZero;
}

- (CGRect)frameForDictationResultPlaceholder:(id)placeholder
{
    return CGRectZero;
}
- (void)insertDictationResult:(NSArray *)dictationResult
{
}
- (id)insertDictationResultPlaceholder
{
    return nil;
}

- (NSInteger)offsetFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition
{
    return 0;
}
- (UITextPosition *)positionFromPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset
{
    return nil;
}
- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset
{
    return nil;
}

- (UITextPosition *)positionWithinRange:(UITextRange *)range farthestInDirection:(UITextLayoutDirection)direction
{
    return nil;
}
- (void)removeDictationResultPlaceholder:(id)placeholder willInsertResult:(BOOL)willInsertResult
{
}
- (void)replaceRange:(UITextRange *)range withText:(NSString *)text
{
}
- (NSArray *)selectionRectsForRange:(UITextRange *)range
{
    return nil;
}
- (void)setBaseWritingDirection:(UITextWritingDirection)writingDirection forRange:(UITextRange *)range
{
}
- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange
{
}

- (NSString *)textInRange:(UITextRange *)range
{
    return nil;
}
- (UITextRange *)textRangeFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition
{
    return nil;
}

@end
