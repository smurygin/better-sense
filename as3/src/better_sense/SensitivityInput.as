package better_sense
{
    import flash.display.InteractiveObject;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.MouseEvent;
    import flash.events.TextEvent;
    import flash.text.TextField;
    import net.wg.gui.components.controls.Slider;
    import net.wg.gui.components.controls.TextInput;
    import net.wg.gui.lobby.settings.ControlsSettings;
    import net.wg.gui.lobby.settings.vo.SettingsControlProp;
    import scaleform.clik.events.SliderEvent;
    import scaleform.clik.events.ComponentEvent;

    /** One field and its existing slider; no separate persistent setting. */
    public final class SensitivityInput
    {
        public var slider:Slider;
        public var input:TextInput;

        private var controls:ControlsSettings;
        private var settingId:String;
        private var modelUpdating:Function;
        private var originalWidth:Number;
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
        private var textField:TextField;

        public function SensitivityInput(owner:ControlsSettings, target:Slider, id:String, updating:Function)
        {
            controls = owner;
            slider = target;
            settingId = id;
            modelUpdating = updating;
            originalWidth = slider.width;
            var fieldWidth:Number = Math.min(104, Math.max(76, originalWidth * 0.38));
            if (originalWidth - fieldWidth - 8 < 48)
                throw new Error("Sensitivity row is too narrow: " + id);
            try
            {
                input = App.utils.classFactory.getComponent("TextInput", TextInput, {
                    name: "betterSense_" + id,
                    width: fieldWidth,
                    height: 30,
                    maxChars: 0,
                    extractEscapes: false
                }) as TextInput;
                if (input == null)
                    throw new Error("Native TextInput linkage is unavailable");
                slider.parent.addChild(input);
                input.validateNow();
                slider.width = originalWidth - fieldWidth - 8;
                input.x = slider.x + slider.width + 8;
                input.y = slider.y + (slider.height - input.height) / 2;
                bindTextField();
                input.addEventListener(ComponentEvent.STATE_CHANGE, onStateChange);
                input.addEventListener(Event.CHANGE, onDraftChanged);
                input.addEventListener(MouseEvent.ROLL_OVER, onRollOver);
                input.addEventListener(MouseEvent.ROLL_OUT, onRollOut);
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
        }

        private function bindTextField():void
        {
            // A skin frame may replace the underlying TextField when focus changes.
            if (textField == input.textField)
                return;
            unbindTextField();
            textField = input.textField;
            if (textField == null)
                throw new Error("Native TextInput has no text field");
            textField.restrict = null; // A character whitelist silently sanitizes paste.
            textField.multiline = false;
            textField.addEventListener(TextEvent.TEXT_INPUT, onTextInput, false, 1000);
            textField.addEventListener(Event.CHANGE, onRawChange, false, 1000);
            textField.addEventListener(FocusEvent.FOCUS_IN, onFocusIn);
            textField.addEventListener(FocusEvent.FOCUS_OUT, onFocusOut);
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

        private function onRawChange(event:Event):void
        {
            if (writingText || disposed)
                return;
            // Also cover paste/IME paths that do not emit cancellable TEXT_INPUT.
            // Roll back the complete edit before the native TextInput sees it.
            if (!DecimalInput.isDraft(input.textField.text))
            {
                setText(lastDraft);
                input.textField.setSelection(selectionStart, selectionEnd);
                event.stopImmediatePropagation();
            }
        }

        private function onDraftChanged(event:Event):void
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
                input.highlight = false;
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
                input.highlight = true;
                showRange();
            }
            else
            {
                stageValue(value);
                setText(DecimalInput.format(value));
                input.highlight = false;
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
            input.highlight = false;
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
        }

        private function setText(text:String):void
        {
            writingText = true;
            try
            {
                input.text = text;
                input.validateNow();
                lastDraft = text;
            }
            finally
            {
                writingText = false;
            }
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
            if (slider != null)
            {
                slider.removeEventListener(SliderEvent.VALUE_CHANGE, onSliderChanged);
                slider.width = originalWidth;
            }
            if (input != null)
            {
                unbindTextField();
                input.removeEventListener(ComponentEvent.STATE_CHANGE, onStateChange);
                input.removeEventListener(Event.CHANGE, onDraftChanged);
                input.removeEventListener(MouseEvent.ROLL_OVER, onRollOver);
                input.removeEventListener(MouseEvent.ROLL_OUT, onRollOut);
                // Move focus while the native window still owns both components.
                if (slider != null && slider.stage != null && ownsFocus(App.utils.focusHandler.getFocus(0)))
                    App.utils.focusHandler.setFocus(slider);
                if (input.parent != null)
                    input.parent.removeChild(input);
                if (input.highlightMc != null)
                    input.dispose();
                input = null;
            }
            controls = null;
            slider = null;
            modelUpdating = null;
        }
    }
}
