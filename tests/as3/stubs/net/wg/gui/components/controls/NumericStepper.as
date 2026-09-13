package net.wg.gui.components.controls
{
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.MouseEvent;
    import flash.text.TextField;
    import flash.ui.Keyboard;
    import scaleform.clik.constants.InputValue;
    import scaleform.clik.constants.NavigationCode;
    import scaleform.clik.events.ButtonEvent;
    import scaleform.clik.events.ComponentEvent;
    import scaleform.clik.events.InputEvent;
    import scaleform.clik.events.IndexEvent;

    /** Source-derived host double: native snapping, label redraw, scheduled edits
     * and lower-priority step handlers. It does not emulate GFx clipboard input. */
    public final class NumericStepper extends Sprite
    {
        public var textField:TextField;
        public var bg:Sprite = new Sprite();
        public var nextBtn1:SoundButton = new SoundButton();
        public var prevBtn1:SoundButton = new SoundButton();
        public var stepSize:Number = 1;
        public var canManualInput:Boolean = true;
        public var isUseLoop:Boolean = false;
        public var wasDisposed:Boolean = false;
        public var nativeChangeCount:int = 0;
        public var nativeStepCount:int = 0;
        public var nativeNormalizationCount:int = 0;
        public var nativeIndexChangeCount:int = 0;

        private var _minimum:Number = 0;
        private var _maximum:Number = 10;
        private var _value:Number = 0;
        private var _integral:Boolean = true;
        private var _enabled:Boolean = true;
        private var _textColorId:String = "mainText";
        private var _labelFunction:Function;
        private var integralInvalid:Boolean = true;
        private var invalid:Boolean = true;
        private var pendingValue:Number = NaN;
        private var controlWidth:Number = 55;
        private var controlHeight:Number = 30;

        public function NumericStepper()
        {
            redrawBackground();
            addChild(bg);
            addChild(nextBtn1);
            addChild(prevBtn1);
            nextBtn1.x = prevBtn1.x = 39;
            nextBtn1.y = 2;
            prevBtn1.y = 16;
            textField = createField();
            nextBtn1.addEventListener(ButtonEvent.CLICK, nativeNext);
            prevBtn1.addEventListener(ButtonEvent.CLICK, nativePrev);
            addEventListener(InputEvent.INPUT, handleInput);
            addEventListener(MouseEvent.MOUSE_WHEEL, nativeWheel);
            addEventListener(Event.ENTER_FRAME, nativeFrame);
            addEventListener(Event.RENDER, nativeFrame);
        }

        private function createField():TextField
        {
            var result:TextField = new TextField();
            result.type = "input";
            result.x = 4;
            result.y = 4;
            result.width = 31;
            result.height = 22;
            result.restrict = _integral ? "0-9" : "0-9.";
            result.addEventListener(Event.CHANGE, nativeChange);
            result.addEventListener(FocusEvent.FOCUS_OUT, nativeBlur);
            addChild(result);
            return result;
        }

        public function setSize(valueWidth:Number, valueHeight:Number):void
        {
            controlWidth = valueWidth;
            controlHeight = valueHeight;
        }

        override public function get width():Number { return controlWidth; }
        override public function set width(value:Number):void { controlWidth = value; }
        override public function get height():Number { return controlHeight; }
        override public function set height(value:Number):void { controlHeight = value; }

        private function redrawBackground():void
        {
            bg.graphics.clear();
            bg.graphics.beginFill(0);
            bg.graphics.drawRect(0, 0, 55, 30);
            bg.graphics.endFill();
        }

        public function get minimum():Number { return _minimum; }
        public function set minimum(value:Number):void
        {
            _minimum = stepSize * Math.floor(value / stepSize);
            this.value = _value;
        }
        public function get maximum():Number { return _maximum; }
        public function set maximum(value:Number):void
        {
            _maximum = stepSize * Math.floor(value / stepSize);
            this.value = _value;
        }
        public function get value():Number { return _value; }
        public function set value(value:Number):void
        {
            var previous:Number = _value;
            value = Math.max(_minimum, Math.min(_maximum, stepSize * Math.round(value / stepSize)));
            if (_value == value)
            {
                updateEnabled();
                return;
            }
            _value = value;
            updateEnabled();
            nativeIndexChangeCount++;
            dispatchEvent(new IndexEvent(IndexEvent.INDEX_CHANGE, true, false, _value, previous));
            invalid = true;
        }
        public function get integral():Boolean { return _integral; }
        public function set integral(value:Boolean):void
        {
            if (_integral != value)
            {
                integralInvalid = true;
                invalid = true;
            }
            _integral = value;
        }
        public function get enabled():Boolean { return _enabled; }
        public function set enabled(value:Boolean):void { _enabled = value; updateEnabled(); }
        public function get textColorId():String { return _textColorId; }
        public function set textColorId(value:String):void
        {
            if (_textColorId == value)
                return;
            _textColorId = value;
            updateLabel();
        }
        public function get labelFunction():Function { return _labelFunction; }
        public function set labelFunction(value:Function):void
        {
            _labelFunction = value;
            updateLabel();
        }

        private function updateEnabled():void
        {
            nextBtn1.enabled = nextBtn1.mouseEnabled = _enabled && (isUseLoop || _value != _maximum);
            prevBtn1.enabled = prevBtn1.mouseEnabled = _enabled && (isUseLoop || _value != _minimum);
            if (textField != null)
            {
                textField.type = _enabled && canManualInput ? "input" : "dynamic";
                textField.selectable = _enabled && canManualInput;
            }
        }

        public function invalidate():void
        {
            invalid = true;
            integralInvalid = true;
        }

        private function nativeFrame(event:Event):void { validateNow(); }

        public function validateNow():void
        {
            if (!invalid && !integralInvalid)
                return;
            var resetIntegral:Boolean = integralInvalid;
            invalid = false;
            integralInvalid = false;
            updateLabel();
            // Native super.draw can dispatch STATE_CHANGE before the subclass
            // reapplies its integral whitelist later in the same validation.
            dispatchEvent(new ComponentEvent(ComponentEvent.STATE_CHANGE));
            if (resetIntegral)
                textField.restrict = _integral ? "0-9" : "0-9.";
            updateEnabled();
        }

        private function updateLabel():void
        {
            if (textField != null)
                textField.text = labelFunction == null ? _value.toString() : labelFunction(_value);
        }

        private function nativeChange(event:Event):void
        {
            nativeChangeCount++;
            var text:String = textField.text;
            while (text.length > 1 && text.substr(0, 2) != "0." && text.charAt(0) == "0")
                text = text.substr(1);
            if (integral)
                text = text.replace(/\.|,/g, "");
            pendingValue = Number(text);
            if (textField.text == "" || isNaN(pendingValue))
                pendingValue = minimum;
        }

        public function flushNativeNormalization():void
        {
            if (isNaN(pendingValue))
                return;
            nativeNormalizationCount++;
            value = pendingValue;
            pendingValue = NaN;
            validateNow();
        }

        private function nativeBlur(event:FocusEvent):void { flushNativeNormalization(); }
        private function nativeNext(event:ButtonEvent):void { nativeStep(1); }
        private function nativePrev(event:ButtonEvent):void { nativeStep(-1); }
        private function nativeStep(direction:int):void
        {
            nativeStepCount++;
            flushNativeNormalization();
            value += direction * stepSize;
            validateNow();
        }
        private function nativeWheel(event:MouseEvent):void
        {
            if (enabled)
                nativeStep(event.delta > 0 ? 1 : -1);
        }

        public function handleInput(event:InputEvent):void
        {
            if (event.isDefaultPrevented())
                return;
            var nav:String = event.details.navEquivalent;
            if (event.details.code == Keyboard.NUMPAD_ADD) nav = NavigationCode.UP;
            if (event.details.code == Keyboard.NUMPAD_SUBTRACT) nav = NavigationCode.DOWN;
            if (nav == NavigationCode.HOME || nav == NavigationCode.END)
            {
                if (event.details.value == InputValue.KEY_UP && !event.details.shiftKey)
                {
                    nativeStepCount++;
                    value = nav == NavigationCode.HOME ? minimum : maximum;
                }
                event.handled = true;
                return;
            }
            if (nav != NavigationCode.UP && nav != NavigationCode.DOWN)
                return;
            if (event.details.value == InputValue.KEY_DOWN || event.details.value == InputValue.KEY_HOLD)
                nativeStep(nav == NavigationCode.UP ? 1 : -1);
            event.handled = true;
        }

        public function replaceSkinField():TextField
        {
            var old:TextField = textField;
            old.removeEventListener(Event.CHANGE, nativeChange);
            old.removeEventListener(FocusEvent.FOCUS_OUT, nativeBlur);
            removeChild(old);
            textField = createField();
            updateLabel();
            dispatchEvent(new ComponentEvent(ComponentEvent.STATE_CHANGE));
            return old;
        }

        public function dispose():void
        {
            wasDisposed = true;
            pendingValue = NaN;
            textField.removeEventListener(Event.CHANGE, nativeChange);
            textField.removeEventListener(FocusEvent.FOCUS_OUT, nativeBlur);
            nextBtn1.removeEventListener(ButtonEvent.CLICK, nativeNext);
            prevBtn1.removeEventListener(ButtonEvent.CLICK, nativePrev);
            removeEventListener(InputEvent.INPUT, handleInput);
            removeEventListener(MouseEvent.MOUSE_WHEEL, nativeWheel);
            removeEventListener(Event.ENTER_FRAME, nativeFrame);
            removeEventListener(Event.RENDER, nativeFrame);
            nextBtn1.dispose();
            prevBtn1.dispose();
        }
    }
}
