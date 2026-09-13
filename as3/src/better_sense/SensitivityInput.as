package better_sense
{
    import flash.display.DisplayObject;
    import flash.display.InteractiveObject;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.events.TextEvent;
    import flash.text.TextField;
    import flash.ui.Keyboard;
    import flash.utils.getDefinitionByName;
    import flash.utils.Dictionary;
    import net.wg.data.constants.generated.TEXT_MANAGER_STYLES;
    import net.wg.gui.components.controls.NumericStepper;
    import net.wg.gui.components.controls.Slider;
    import net.wg.gui.lobby.settings.ControlsSettings;
    import net.wg.gui.lobby.settings.vo.SettingsControlProp;
    import scaleform.clik.events.SliderEvent;
    import scaleform.clik.events.ComponentEvent;
    import scaleform.clik.constants.InputValue;
    import scaleform.clik.events.ButtonEvent;
    import scaleform.clik.events.InputEvent;
    import scaleform.clik.events.IndexEvent;

    /** One field and its existing slider; no separate persistent setting. */
    public final class SensitivityInput
    {
        private static const MIN_INPUT_WIDTH:Number = 92;
        private static const INPUT_GAP:Number = 8;
        private static const ARROW_RIGHT_PADDING:Number = 3;
        private static const TEXT_ARROW_GAP:Number = 4;

        public var slider:Slider;
        public var input:NumericStepper;

        private var controls:ControlsSettings;
        private var settingId:String;
        private var modelUpdating:Function;
        private var originalWidth:Number;
        private var inputWidth:Number;
        private var acceptedValue:Number = NaN;
        private var editOrigin:Number = NaN;
        private var lastDraft:String = "";
        private var selectionStart:int = 0;
        private var selectionEnd:int = 0;
        private var editing:Boolean = false;
        private var touched:Boolean = false;
        private var writingSlider:Boolean = false;
        private var writingText:Boolean = false;
        private var disposed:Boolean = false;
        private var nativeReady:Boolean = false;
        private var inputError:Boolean = false;
        private var textField:TextField;
        private var clipboardReader:Function;
        private var skinRightInsets:Dictionary;

        public function SensitivityInput(owner:ControlsSettings, target:Slider, id:String,
            updating:Function, readClipboard:Function = null)
        {
            controls = owner;
            slider = target;
            settingId = id;
            modelUpdating = updating;
            clipboardReader = readClipboard;
            originalWidth = slider.width;
            try
            {
                input = App.utils.classFactory.getComponent("NumericStepper", NumericStepper, {
                    name: "betterSense_" + id
                }) as NumericStepper;
                if (input == null)
                    throw new Error("Native NumericStepper linkage is unavailable");
                input.addEventListener(IndexEvent.INDEX_CHANGE, onNativeValueChanged, false, 1000);
                slider.parent.addChild(input);
                input.validateNow();
                if (input.nextBtn1 == null || input.prevBtn1 == null)
                    throw new Error("Native NumericStepper has no arrow buttons");
                captureInputSkins(input.width);
                inputWidth = Math.max(MIN_INPUT_WIDTH, input.width);
                input.setSize(inputWidth, input.height);
                input.validateNow();
                layoutInput();
                if (!isFinite(inputWidth) || inputWidth <= 0 || originalWidth - inputWidth - INPUT_GAP < 48)
                    throw new Error("Sensitivity row is too narrow: " + id);
                nativeReady = true;
                // Native value/bounds setters require initialized arrow buttons.
                input.integral = false;
                input.isUseLoop = false;
                input.canManualInput = true;
                input.stepSize = stepInterval > 0 ? stepInterval : 0.000001;
                input.minimum = slider.minimum;
                input.maximum = maximum;
                input.labelFunction = formatDraft;
                input.validateNow();
                slider.width = originalWidth - inputWidth - INPUT_GAP;
                input.x = slider.x + slider.width + INPUT_GAP;
                input.y = slider.y + (slider.height - input.height) / 2;
                bindTextField();
                input.addEventListener(ComponentEvent.STATE_CHANGE, onStateChange);
                input.addEventListener(Event.ENTER_FRAME, onValidated, false, -1000);
                input.addEventListener(Event.RENDER, onValidated, false, -1000);
                input.addEventListener(MouseEvent.ROLL_OVER, onRollOver);
                input.addEventListener(MouseEvent.ROLL_OUT, onRollOut);
                input.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel, false, 1000);
                input.addEventListener(InputEvent.INPUT, onStepperInput, true, 1000);
                input.addEventListener(InputEvent.INPUT, onStepperInput, false, 1000);
                App.stage.addEventListener(KeyboardEvent.KEY_DOWN, onStageKeyDown, true, 2000);
                input.nextBtn1.addEventListener(ButtonEvent.CLICK, onNext, false, 1000);
                input.prevBtn1.addEventListener(ButtonEvent.CLICK, onPrev, false, 1000);
                slider.addEventListener(SliderEvent.VALUE_CHANGE, onSliderChanged, false, 1000);
            }
            catch (error:Error)
            {
                dispose();
                throw error;
            }
        }

        private function onStateChange(event:ComponentEvent):void
        {
            bindTextField();
            updateArrows();
        }

        private function onValidated(event:Event):void
        {
            if (disposed)
                return;
            // Native validation runs at priority 0. Its draw can restore the
            // character whitelist AFTER STATE_CHANGE; repair it after the draw.
            input.validateNow();
            bindTextField();
            updateArrows();
        }

        private function bindTextField():void
        {
            // A skin frame may replace the underlying TextField when focus changes.
            if (textField != input.textField)
            {
                unbindTextField();
                textField = input.textField;
                if (textField == null)
                    throw new Error("Native NumericStepper has no text field");
                textField.addEventListener(TextEvent.TEXT_INPUT, onTextInput, false, 1000);
                textField.addEventListener(Event.CHANGE, onRawChange, false, 1000);
                textField.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
                textField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            }
            // integral=false installs a native whitelist during its draw pass.
            // Clear it only after validation, including when the field is reused.
            textField.restrict = null; // A character whitelist silently sanitizes paste.
            textField.multiline = false;
            textField.maxChars = 0;
            layoutInput();
        }

        private function layoutInput():void
        {
            if (input == null || input.textField == null || input.nextBtn1 == null ||
                input.prevBtn1 == null || !isFinite(inputWidth) || inputWidth <= 0)
            {
                return;
            }
            // NumericStepper.initItems() runs only during configUI(). Resizing an
            // initialized linkage does not repeat its timeline layout, so repair
            // the skin, arrows and text field explicitly after every state change.
            for (var key:Object in skinRightInsets)
            {
                var skin:DisplayObject = key as DisplayObject;
                if (skin != null && skin.parent == input)
                    skin.width = Math.max(1, inputWidth - skin.x - Number(skinRightInsets[key]));
            }
            var arrowWidth:Number = Math.max(input.nextBtn1.width, input.prevBtn1.width);
            var arrowX:Number = Math.round(inputWidth - arrowWidth - ARROW_RIGHT_PADDING);
            input.nextBtn1.x = input.prevBtn1.x = arrowX;
            input.textField.width = Math.max(1,
                arrowX - input.textField.x - TEXT_ARROW_GAP);
        }

        private function captureInputSkins(authoredWidth:Number):void
        {
            skinRightInsets = new Dictionary(true);
            for (var index:int = 0; index < input.numChildren; index++)
            {
                var child:DisplayObject = input.getChildAt(index);
                if (child != input.nextBtn1 && child != input.prevBtn1 &&
                    child != input.textField && isFinite(child.width) && child.width > 0)
                {
                    skinRightInsets[child] = authoredWidth - child.x - child.width;
                }
            }
        }

        private function unbindTextField():void
        {
            if (textField == null)
                return;
            textField.removeEventListener(TextEvent.TEXT_INPUT, onTextInput);
            textField.removeEventListener(Event.CHANGE, onRawChange);
            textField.removeEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            textField.removeEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
            textField = null;
        }

        private function get maximum():Number
        {
            var cap:Number = slider.maxAvailableValue;
            return isNaN(cap) ? slider.maximum : Math.min(slider.maximum, cap);
        }

        private function get stepInterval():Number
        {
            return isFinite(slider.snapInterval) && slider.snapInterval > 0 ? slider.snapInterval : 0;
        }

        public function get hasInputError():Boolean
        {
            return inputError;
        }

        private function get modelValue():Number
        {
            if (controls.data == null)
                return NaN;
            var property:SettingsControlProp = controls.data.getByKey(settingId) as SettingsControlProp;
            return property == null || property.current == null ? NaN : Number(property.current);
        }

        public function refresh():void
        {
            if (disposed)
                return;
            input.enabled = slider.enabled && isFinite(modelValue);
            input.stepSize = stepInterval > 0 ? stepInterval : 0.000001;
            input.minimum = slider.minimum;
            input.maximum = maximum;
            if (!editing)
            {
                // The model is authoritative on initial hydration, including values
                // that stock setData might already have snapped for display.
                var value:Number = modelValue;
                if (isNaN(acceptedValue) && isFinite(value))
                {
                    slider.position = value;
                    slider.invalidate();
                    acceptedValue = value;
                }
                if (isFinite(acceptedValue))
                    setText(DecimalInput.format(acceptedValue));
            }
            updateArrows();
        }

        public function ownsFocus(focus:InteractiveObject):Boolean
        {
            return input != null && focus != null && (focus == input || input.contains(focus));
        }

        private function onTextInput(event:TextEvent):void
        {
            var field:TextField = input.textField;
            selectionStart = field.selectionBeginIndex;
            selectionEnd = field.selectionEndIndex;
            if (DecimalInput.replacement(field.text, selectionStart, selectionEnd, event.text) == null)
            {
                event.preventDefault();
                event.stopImmediatePropagation();
            }
        }

        private function pasteText(pasted:String):void
        {
            var field:TextField = input.textField;
            selectionStart = field.selectionBeginIndex;
            selectionEnd = field.selectionEndIndex;
            var draft:String = DecimalInput.replacement(
                field.text, selectionStart, selectionEnd, pasted);
            if (draft == null)
                return;
            writingText = true;
            try
            {
                field.text = draft;
                var caret:int = selectionStart + pasted.length;
                field.setSelection(caret, caret);
            }
            finally
            {
                writingText = false;
            }
            onDraftChanged();
        }

        public function pasteClipboard():Boolean
        {
            var pasted:String = readClipboardText();
            if (pasted == null)
                return false;
            pasteText(pasted);
            return true;
        }

        private function readClipboardText():String
        {
            var value:Object = null;
            try
            {
                if (clipboardReader != null)
                {
                    value = clipboardReader();
                    if (value != null)
                        return String(value);
                }
            }
            catch (bridgeError:Error)
            {
                // Keep the Flash fallback available if the Python bridge fails.
            }
            try
            {
                // Resolve dynamically so a client that hides this Flash API can
                // fall back to the native TextField editor without a VerifyError.
                var clipboardClass:Object = getDefinitionByName("flash.desktop.Clipboard");
                var formatsClass:Object = getDefinitionByName("flash.desktop.ClipboardFormats");
                value = clipboardClass.generalClipboard.getData(formatsClass.TEXT_FORMAT);
                return value == null ? null : String(value);
            }
            catch (error:Error)
            {
                return null;
            }
        }

        private function onRawChange(event:Event):void
        {
            if (disposed)
                return;
            // The native stepper would strip/parse text, round it to stepSize,
            // and schedule normalization. Own the complete edit before it runs.
            event.stopImmediatePropagation();
            if (writingText)
                return;
            // Also cover paste/IME paths that do not emit cancellable TEXT_INPUT.
            // Roll back the complete edit before native stepper normalization.
            if (!DecimalInput.isDraft(input.textField.text))
            {
                setText(lastDraft);
                input.textField.setSelection(selectionStart, selectionEnd);
                return;
            }
            onDraftChanged();
        }

        private function onDraftChanged():void
        {
            if (writingText || disposed)
                return;
            var draft:String = input.textField.text;
            if (!DecimalInput.isDraft(draft))
                return;
            lastDraft = draft;
            touched = true;
            var value:Number = DecimalInput.parse(draft, slider.minimum, maximum);
            if (!isNaN(value))
            {
                // Preview in the window's change set so Apply becomes available.
                // Actual preferences are still written only by stock Apply/OK.
                stageValue(value);
                setError(false);
            }
        }

        private function onFocusIn(event:FocusEvent):void
        {
            editing = true;
            touched = false;
            editOrigin = acceptedValue;
            lastDraft = input.textField.text;
        }

        private function onFocusOut(event:FocusEvent):void
        {
            if (disposed)
                return;
            commit();
            editing = false;
        }

        public function commit():void
        {
            if (disposed || !touched)
                return;
            var value:Number = DecimalInput.parse(input.textField.text, slider.minimum, maximum);
            if (isNaN(value))
            {
                setText(DecimalInput.format(acceptedValue));
                setError(true);
                showRange();
            }
            else
            {
                stageValue(value);
                setText(DecimalInput.format(value));
                setError(false);
            }
            touched = false;
            editOrigin = acceptedValue;
        }

        public function cancelEdit():void
        {
            if (isFinite(editOrigin))
                stageValue(editOrigin);
            setText(DecimalInput.format(acceptedValue));
            touched = false;
            setError(false);
            App.toolTipMgr.hide();
        }

        public function abandon():void
        {
            touched = false;
            editing = false;
        }

        private function stageValue(value:Number):void
        {
            // parse() must have checked syntax at the boundary. Defend this numeric
            // boundary as well, including callers restoring the focus snapshot.
            if (!isFinite(value) || value < slider.minimum || value > maximum)
                return;
            acceptedValue = value;
            updateArrows();
            if (slider.value == value)
                return;
            writingSlider = true;
            try
            {
                slider.position = value; // value= would round to snapInterval.
                slider.invalidate();
                slider.dispatchEvent(new SliderEvent(SliderEvent.VALUE_CHANGE, false, true, value));
            }
            finally
            {
                writingSlider = false;
            }
        }

        private function onSliderChanged(event:SliderEvent):void
        {
            if (disposed || writingSlider)
                return;
            if (Boolean(modelUpdating()))
            {
                var precise:Number = modelValue;
                if (isFinite(precise))
                {
                    slider.position = precise;
                    event.value = precise;
                    slider.invalidate();
                }
            }
            acceptedValue = slider.value;
            editOrigin = acceptedValue;
            touched = false;
            setText(DecimalInput.format(acceptedValue));
            setError(false);
        }

        private function setText(text:String):void
        {
            writingText = true;
            try
            {
                lastDraft = text;
                // Native numeric state drives the skin only. Its step rounding
                // must never replace the precise coefficient in acceptedValue.
                if (isFinite(acceptedValue))
                    input.value = acceptedValue;
                input.labelFunction = formatDraft;
                input.validateNow();
                bindTextField();
                updateArrows();
            }
            finally
            {
                writingText = false;
            }
        }

        private function formatDraft(value:Number):String
        {
            return lastDraft;
        }

        private function onNativeValueChanged(event:IndexEvent):void
        {
            // Its rounded value is skin state, never a second settings source.
            if (event.target == input)
                event.stopImmediatePropagation();
        }

        private function setError(value:Boolean):void
        {
            if (inputError == value)
                return;
            inputError = value;
            var start:int = input.textField.selectionBeginIndex;
            var end:int = input.textField.selectionEndIndex;
            input.textColorId = value ? TEXT_MANAGER_STYLES.ERROR_TEXT : TEXT_MANAGER_STYLES.MAIN_TEXT;
            input.labelFunction = formatDraft;
            input.textField.setSelection(start, end);
        }

        private function updateArrows():void
        {
            if (input == null || !nativeReady || input.nextBtn1 == null || input.prevBtn1 == null)
                return;
            var available:Boolean = input.enabled && slider.enabled && isFinite(acceptedValue) && stepInterval > 0;
            input.nextBtn1.enabled = input.nextBtn1.mouseEnabled = available && acceptedValue < maximum;
            input.prevBtn1.enabled = input.prevBtn1.mouseEnabled = available && acceptedValue > slider.minimum;
        }

        private function stepBy(direction:int):void
        {
            if (disposed || !input.enabled || !slider.enabled || stepInterval == 0 || !isFinite(acceptedValue))
                return;
            commit();
            var value:Number = Number(DecimalInput.format(acceptedValue + direction * stepInterval));
            value = Math.max(slider.minimum, Math.min(maximum, value));
            stageValue(value);
            editOrigin = acceptedValue;
            touched = false;
            setText(DecimalInput.format(acceptedValue));
            setError(false);
            App.toolTipMgr.hide();
        }

        private function onNext(event:ButtonEvent):void
        {
            event.preventDefault();
            event.stopImmediatePropagation();
            stepBy(1);
        }

        private function onPrev(event:ButtonEvent):void
        {
            event.preventDefault();
            event.stopImmediatePropagation();
            stepBy(-1);
        }

        private function onMouseWheel(event:MouseEvent):void
        {
            event.preventDefault();
            event.stopImmediatePropagation();
            if (event.delta != 0)
                stepBy(event.delta > 0 ? 1 : -1);
        }

        private function onStepperInput(event:InputEvent):void
        {
            if (disposed || event.handled)
                return;
            var code:uint = event.details.code;
            if (event.details.ctrlKey && code == Keyboard.V)
            {
                if (event.details.value != InputValue.KEY_DOWN)
                    return;
                // TextField does not dispatch Event.PASTE. Read during the actual
                // user key event, then own the full replacement before native
                // NumericStepper sanitization. If access is unavailable, preserve
                // the client's normal Ctrl+V path.
                if (!pasteClipboard())
                    return;
                event.handled = true;
                event.preventDefault();
                event.stopImmediatePropagation();
                return;
            }
            selectionStart = input.textField.selectionBeginIndex;
            selectionEnd = input.textField.selectionEndIndex;
            var direction:int = code == Keyboard.UP || code == Keyboard.NUMPAD_ADD ? 1 :
                (code == Keyboard.DOWN || code == Keyboard.NUMPAD_SUBTRACT ? -1 : 0);
            if (direction == 0 && code != Keyboard.HOME && code != Keyboard.END)
                return; // Leave clipboard commands and ordinary text editing native.
            event.handled = true;
            event.preventDefault();
            event.stopImmediatePropagation();
            if (event.details.value != InputValue.KEY_DOWN && event.details.value != InputValue.KEY_HOLD)
                return;
            if (direction != 0)
                stepBy(direction);
            else
            {
                // Home/End edit the text caret; native numeric min/max shortcuts
                // would instead mutate only the stepper's rounded skin value.
                var field:TextField = input.textField;
                var edge:int = code == Keyboard.HOME ? 0 : field.text.length;
                var anchor:int = edge;
                if (event.details.shiftKey)
                    anchor = field.caretIndex == field.selectionBeginIndex ? field.selectionEndIndex : field.selectionBeginIndex;
                field.setSelection(anchor, edge);
            }
        }

        private function onStageKeyDown(event:KeyboardEvent):void
        {
            if (disposed || !event.ctrlKey || event.keyCode != Keyboard.V ||
                !ownsFocus(App.utils.focusHandler.getFocus(0)) || !pasteClipboard())
            {
                return;
            }
            // This runs before CLIK InputDelegate and the settings window. Stop
            // the native event so the TextField cannot apply the same paste twice.
            event.preventDefault();
            event.stopImmediatePropagation();
        }

        private function showRange():void
        {
            App.toolTipMgr.showComplex("<body>Введите число от " + DecimalInput.format(slider.minimum) +
                " до " + DecimalInput.format(maximum) + ". Разделитель: точка или запятая; до 6 знаков после него.</body>");
        }

        private function onRollOver(event:MouseEvent):void
        {
            showRange();
        }

        private function onRollOut(event:MouseEvent):void
        {
            App.toolTipMgr.hide();
        }

        public function dispose():void
        {
            if (disposed)
                return;
            disposed = true;
            if (App.stage != null)
                App.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onStageKeyDown, true);
            if (slider != null)
            {
                slider.removeEventListener(SliderEvent.VALUE_CHANGE, onSliderChanged);
                slider.width = originalWidth;
            }
            if (input != null)
            {
                unbindTextField();
                input.removeEventListener(ComponentEvent.STATE_CHANGE, onStateChange);
                input.removeEventListener(Event.ENTER_FRAME, onValidated);
                input.removeEventListener(Event.RENDER, onValidated);
                input.removeEventListener(IndexEvent.INDEX_CHANGE, onNativeValueChanged);
                input.removeEventListener(MouseEvent.ROLL_OVER, onRollOver);
                input.removeEventListener(MouseEvent.ROLL_OUT, onRollOut);
                input.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
                input.removeEventListener(InputEvent.INPUT, onStepperInput, true);
                input.removeEventListener(InputEvent.INPUT, onStepperInput);
                if (input.nextBtn1 != null)
                    input.nextBtn1.removeEventListener(ButtonEvent.CLICK, onNext);
                if (input.prevBtn1 != null)
                    input.prevBtn1.removeEventListener(ButtonEvent.CLICK, onPrev);
                // Move focus while the native window still owns both components.
                if (slider != null && slider.stage != null && ownsFocus(App.utils.focusHandler.getFocus(0)))
                    App.utils.focusHandler.setFocus(slider);
                if (input.parent != null)
                    input.parent.removeChild(input);
                if (nativeReady)
                    input.dispose();
                input = null;
            }
            controls = null;
            slider = null;
            modelUpdating = null;
            clipboardReader = null;
            skinRightInsets = null;
        }
    }
}
