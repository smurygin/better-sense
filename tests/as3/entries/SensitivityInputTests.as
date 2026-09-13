package
{
    import better_sense.SensitivityInput;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.MouseEvent;
    import flash.events.KeyboardEvent;
    import flash.events.TextEvent;
    import flash.external.ExternalInterface;
    import flash.text.TextField;
    import flash.ui.Keyboard;
    import net.wg.data.constants.generated.TEXT_MANAGER_STYLES;
    import net.wg.gui.components.controls.Slider;
    import net.wg.gui.components.controls.NumericStepper;
    import net.wg.gui.lobby.settings.ControlsSettings;
    import net.wg.gui.lobby.settings.vo.SettingsControlProp;
    import scaleform.clik.events.SliderEvent;
    import scaleform.clik.events.ButtonEvent;
    import scaleform.clik.events.InputEvent;
    import scaleform.clik.events.IndexEvent;
    import scaleform.clik.constants.InputValue;
    import scaleform.clik.constants.NavigationCode;
    import scaleform.clik.ui.InputDetails;

    /** Executes production binding logic with a small documented native protocol double. */
    public final class SensitivityInputTests extends Sprite
    {
        private var assertions:int = 0;
        private var controls:ControlsSettings;
        private var slider:Slider;
        private var row:SensitivityInput;
        private var property:SettingsControlProp;
        private var updating:Boolean;
        private var observed:Array;
        private var observedNativeIndices:Array;
        private var clipboardText:String;

        public function SensitivityInputTests()
        {
            if (stage == null)
                addEventListener(Event.ADDED_TO_STAGE, run);
            else
                run();
        }

        private function run(event:Event = null):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, run);
            App.stage = stage;
            testHydrationAndPrecision();
            testEditingAndSourceEvents();
            testInvalidEdits();
            testNativePasteChanges();
            testNativeStepperRedraw();
            testNativeIndexIsolation();
            testNativeFrameValidation();
            testStepperButtons();
            testStepperKeyboardAndWheel();
            testStageClipboardCommand();
            testClipboardCommand();
            testClipboardCommandPassthrough();
            testHomeEndSelection();
            testStepperLimitsAndDisabled();
            testUnavailableStep();
            testEscapeAndReset();
            testSkinAndDisposal();
            report(true, assertions + " binding assertions passed");
        }

        private function fixture(value:Number):void
        {
            if (row != null)
                row.dispose();
            if (controls != null && controls.parent != null)
                controls.parent.removeChild(controls);
            controls = new ControlsSettings();
            addChild(controls);
            slider = new Slider();
            controls.addChild(slider);
            property = new SettingsControlProp(value);
            controls.data = {getByKey: function(id:String):Object { return property; }};
            slider.position = Math.round(value / slider.snapInterval) * slider.snapInterval;
            updating = false;
            clipboardText = null;
            observed = [];
            observedNativeIndices = [];
            controls.addEventListener(IndexEvent.INDEX_CHANGE, function(event:IndexEvent):void {
                observedNativeIndices.push(event.index);
            });
            row = new SensitivityInput(controls, slider, "mouseArcadeSens",
                function():Boolean { return updating; },
                function():String { return clipboardText; });
            slider.addEventListener(SliderEvent.VALUE_CHANGE, function(event:SliderEvent):void {
                observed.push(slider.value);
            });
            row.refresh();
        }

        private function focus():void
        {
            App.focused = row.input;
            row.input.textField.dispatchEvent(new FocusEvent(FocusEvent.FOCUS_IN));
        }

        private function blur():void
        {
            row.input.textField.dispatchEvent(new FocusEvent(FocusEvent.FOCUS_OUT));
            App.focused = null;
        }

        private function replace(insertion:String):Boolean
        {
            var field:TextField = row.input.textField;
            field.setSelection(0, field.text.length);
            var event:TextEvent = new TextEvent(TextEvent.TEXT_INPUT, true, true, insertion);
            if (!field.dispatchEvent(event))
                return false;
            field.text = insertion;
            field.setSelection(insertion.length, insertion.length);
            field.dispatchEvent(new Event(Event.CHANGE, true));
            return true;
        }

        private function testHydrationAndPrecision():void
        {
            fixture(0.123456789);
            same(slider.value, 0.123456789, "initial attach restores full model precision");
            same(row.input.textField.text, "0.123457", "initial display rounds only its text");
            same(observed.length, 0, "initial attach does not dirty settings");
            same(row.input.width, 92, "authored stepper width is preserved");
            same(slider.width, 100, "slider yields exactly the authored stepper width and gap");
            check(row.input.textField.x + row.input.textField.width <= row.input.nextBtn1.x,
                "authored arrows do not overlap the value field");
            check(row.input.nextBtn1.x + row.input.nextBtn1.width <= row.input.width,
                "authored arrows remain fully inside the stepper");
            check(row.input.bg.x + row.input.bg.width >= row.input.nextBtn1.x + row.input.nextBtn1.width,
                "visible input background reaches the relocated arrows");
            check(row.input.textField.textWidth + 4 <= row.input.textField.width,
                "full six-decimal value fits without horizontal clipping");
            focus();
            blur();
            same(slider.value, 0.123456789, "focus and blur without editing preserve precision");
            same(observed.length, 0, "untouched focus emits no setting change");
            property.current = 0.7654321;
            updating = true;
            slider.value = Number(property.current);
            updating = false;
            row.refresh();
            same(slider.value, 0.7654321, "stock hydration snapping corrected before stock observer");
            same(observed[0], 0.7654321, "stock observer receives precise model value");
            same(row.input.textField.text, "0.765432", "field follows refreshed model");
            same(slider.snapping, true, "native snapping option preserved");
            same(slider.snapInterval, 0.1, "native snap interval preserved");
        }

        private function testEditingAndSourceEvents():void
        {
            fixture(0.5);
            focus();
            check(replace("0,123456"), "comma coefficient accepted");
            same(slider.value, 0.123456, "exact coefficient sent through existing slider");
            same(observed.length, 1, "raw and native CHANGE produce one setting event");
            row.commit();
            same(observed.length, 1, "commit does not duplicate preview event");
            same(row.input.textField.text, "0.123456", "commit canonicalizes separator");
            blur();
            same(observed.length, 1, "blur after commit does not duplicate event");
            slider.value = 0.94;
            same(slider.value, 0.9, "native slider keeps native snapping");
            same(row.input.textField.text, "0.9", "native slider change synchronizes input");
            same(observed.length, 2, "native slider emits one stock change");
            slider.enabled = false;
            row.refresh();
            check(!row.input.enabled, "field disabled with its slider");
            slider.enabled = true;
            property.current = null;
            row.refresh();
            check(!row.input.enabled, "field disabled for unavailable setting");
        }

        private function testInvalidEdits():void
        {
            fixture(0.5);
            focus();
            check(!replace("1e-6"), "invalid scientific paste cancelled whole");
            same(row.input.textField.text, "0.5", "cancelled paste leaves displayed text intact");
            same(observed.length, 0, "cancelled paste emits no settings event");
            row.input.textField.text = "1e-6";
            row.input.textField.dispatchEvent(new Event(Event.CHANGE, true));
            same(row.input.textField.text, "0.5", "raw change fallback rolls back invalid input");
            same(row.input.nativeChangeCount, 0, "rollback prevents native stepper normalization");
            same(observed.length, 0, "raw invalid edit cannot reach stock settings");
            check(replace("1."), "incomplete decimal remains editable");
            same(slider.value, 0.5, "incomplete draft cannot change numeric source");
            row.commit();
            same(row.input.textField.text, "0.5", "incomplete commit restores accepted value");
            check(row.hasInputError, "incomplete commit indicates rejected draft");
            check(replace("9"), "out-of-range draft remains editable");
            same(slider.value, 0.5, "out-of-range draft does not clamp or stage");
            blur();
            same(row.input.textField.text, "0.5", "out-of-range blur restores accepted value");
            same(observed.length, 0, "invalid commit emits no stock change");
        }

        private function testNativePasteChanges():void
        {
            // GFx can replace selected clipboard text and emit CHANGE without
            // TEXT_INPUT. Exercise that boundary independently of typed input.
            var valid:Array = ["1", "0.25", "0,25", "0.000001"];
            var text:String;
            for each (text in valid)
            {
                fixture(0.5);
                focus();
                rawPaste(text);
                same(row.input.textField.text, text, "native paste updates field: " + text);
                same(row.input.nativeChangeCount, 0, "native paste avoids integer normalization: " + text);
                same(slider.value, Number(text.replace(",", ".")), "native paste updates slider: " + text);
                same(observed.length, 1, "native paste emits one setting change: " + text);
            }

            var invalid:Array = ["1e-6", "1E3", "0.2x", "0.2 ", "0.2.3", "0,2.3", "0.1234567"];
            for each (text in invalid)
            {
                fixture(0.5);
                focus();
                rawPaste(text);
                same(row.input.textField.text, "0.5", "native invalid paste rolls back whole: " + text);
                same(row.input.nativeChangeCount, 0, "native invalid paste cannot schedule normalization: " + text);
                same(slider.value, 0.5, "native invalid paste preserves slider: " + text);
                same(observed.length, 0, "native invalid paste emits no setting change: " + text);
            }
        }

        private function rawPaste(text:String):void
        {
            var field:TextField = row.input.textField;
            field.setSelection(0, field.text.length);
            field.replaceSelectedText(text);
            field.dispatchEvent(new Event(Event.CHANGE, true));
        }

        private function testNativeStepperRedraw():void
        {
            fixture(0.123456789);
            check(row.input is NumericStepper, "field uses native NumericStepper protocol");
            same(row.input.stepSize, slider.snapInterval, "native arrows use the slider step");
            check(!row.input.integral && row.input.canManualInput && !row.input.isUseLoop,
                "stepper supports manual fractions without wrapping");
            row.input.validateNow();
            same(row.input.textField.text, "0.123457", "redraw cannot display rounded native stepper value");
            same(slider.value, 0.123456789, "native stepper rounding cannot change hydrated precision");
            same(observed.length, 0, "native redraw cannot dirty initial settings");

            focus();
            replace("0,234567");
            row.input.validateNow();
            same(row.input.textField.text, "0,234567", "data redraw preserves comma draft");
            row.input.flushNativeNormalization();
            same(row.input.nativeChangeCount, 0, "manual change never enters native delayed sanitizer");
            same(row.input.nativeNormalizationCount, 0, "no delayed normalization can round manual entry");
            same(slider.value, 0.234567, "manual coefficient retains six decimals");
            row.input.replaceSkinField();
            same(row.input.textField.text, "0,234567", "state redraw preserves comma draft");
            same(row.input.textField.restrict, null, "replacement native field preserves whole-paste validation");
            replace("0,");
            row.input.validateNow();
            same(row.input.textField.text, "0,", "redraw preserves an incomplete decimal draft");
            same(slider.value, 0.234567, "incomplete redraw leaves accepted coefficient intact");
            row.commit();
            check(row.hasInputError, "incomplete draft exposes validation error");
            same(row.input.textColorId, TEXT_MANAGER_STYLES.ERROR_TEXT, "error uses native text style");
            replace("0,345678");
            same(row.input.textField.text, "0,345678", "clearing native error style preserves current draft");
            check(!row.hasInputError, "valid decimal clears previous validation error");
            same(row.input.textColorId, TEXT_MANAGER_STYLES.MAIN_TEXT, "valid input restores native text style");
        }

        private function clickNext():void
        {
            row.input.nextBtn1.dispatchEvent(new ButtonEvent(ButtonEvent.CLICK));
        }

        private function testNativeIndexIsolation():void
        {
            fixture(0.123456789);
            check(row.input.nativeIndexChangeCount > 0, "native rounded value setter really emits index events");
            same(observedNativeIndices.length, 0, "native hydration indices cannot bubble to ControlsSettings");
            focus();
            replace("0,234567");
            row.commit();
            row.input.invalidate();
            row.input.dispatchEvent(new Event(Event.ENTER_FRAME));
            clickNext();
            same(observedNativeIndices.length, 0, "manual, skin and button indices remain isolated from settings");
            var value:Number = slider.value;
            var count:int = observed.length;
            row.input.value = 0.9;
            row.input.validateNow();
            same(slider.value, value, "native rounded skin value cannot become a settings source");
            same(observed.length, count, "skin-only index emits no slider settings event");
            same(observedNativeIndices.length, 0, "direct native index cannot reach ControlsSettings");
        }

        private function testNativeFrameValidation():void
        {
            for each (var eventType:String in [Event.ENTER_FRAME, Event.RENDER])
            {
                fixture(0.223456);
                slider.maxAvailableValue = 0.25;
                row.refresh();
                focus();
                replace("0,223456");
                row.input.invalidate();
                row.input.dispatchEvent(new Event(eventType));
                same(row.input.textField.restrict, null, "post-draw clears native whitelist after " + eventType);
                same(row.input.textField.text, "0,223456", "post-draw preserves exact draft after " + eventType);
                same(slider.value, 0.223456, "native frame cannot change precise accepted value after " + eventType);
                check(row.input.nextBtn1.enabled, "post-draw restores up button below precise cap after " + eventType);
                check(row.input.prevBtn1.enabled, "post-draw restores down button above precise minimum after " + eventType);
                same(observed.length, 0, "frame redraw emits no settings change after " + eventType);
                same(observedNativeIndices.length, 0, "frame skin events do not reach settings after " + eventType);
            }
        }

        private function clickPrev():void
        {
            row.input.prevBtn1.dispatchEvent(new ButtonEvent(ButtonEvent.CLICK));
        }

        private function testStepperButtons():void
        {
            fixture(0.123456);
            focus();
            clickNext();
            same(slider.value, 0.223456, "up arrow adds slider step without rounding precise coefficient");
            same(row.input.textField.text, "0.223456", "up arrow synchronizes decimal display");
            same(observed.length, 1, "one up click emits exactly one settings event");
            clickNext();
            clickNext();
            same(slider.value, 0.423456, "repeated native button clicks each add one step");
            same(observed.length, 3, "repeat clicks do not duplicate stock notifications");
            clickPrev();
            same(slider.value, 0.323456, "down arrow subtracts slider step");
            same(row.input.textField.text, "0.323456", "down arrow synchronizes decimal display");
            same(row.input.nativeStepCount, 0, "mod intercepts native rounded button stepping");
            same(row.input.nativeNormalizationCount, 0, "button path cannot normalize a pending native draft");
            row.commit();
            blur();
            same(observed.length, 4, "commit and blur do not duplicate arrow updates");
            fixture(0.5);
            focus();
            replace("0,234567");
            clickNext();
            same(slider.value, 0.334567, "arrow starts at accepted manual decimal");
            same(row.input.textField.text, "0.334567", "arrow canonicalizes comma draft");
        }

        private function inputKey(code:uint, state:String, nav:String = null, child:Boolean = false,
            ctrl:Boolean = false, shift:Boolean = false):InputEvent
        {
            var event:InputEvent = new InputEvent(InputEvent.INPUT,
                new InputDetails("key", code, state, nav, 0, ctrl, false, shift));
            if (child)
                row.input.textField.dispatchEvent(event);
            else
                row.input.dispatchEvent(event);
            return event;
        }

        private function wheel(delta:int):void
        {
            row.input.textField.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_WHEEL,
                true, true, 0, 0, null, false, false, false, false, delta));
        }

        private function testStepperKeyboardAndWheel():void
        {
            fixture(0.123456);
            focus();
            var down:InputEvent = inputKey(Keyboard.UP, InputValue.KEY_DOWN, NavigationCode.UP);
            same(slider.value, 0.223456, "keyboard up adds exactly one precise step");
            check(down.handled && down.isDefaultPrevented(), "keyboard step prevents native fallback");
            inputKey(Keyboard.UP, InputValue.KEY_UP, NavigationCode.UP);
            same(observed.length, 1, "key release does not add another step");
            inputKey(Keyboard.UP, InputValue.KEY_HOLD, NavigationCode.UP, true);
            same(slider.value, 0.323456, "held key bubbling from field adds exactly one step");
            inputKey(Keyboard.DOWN, InputValue.KEY_DOWN, NavigationCode.DOWN, true);
            same(slider.value, 0.223456, "keyboard down subtracts one precise step");
            inputKey(Keyboard.NUMPAD_ADD, InputValue.KEY_DOWN);
            same(slider.value, 0.323456, "numpad plus adds one precise step");
            inputKey(Keyboard.NUMPAD_SUBTRACT, InputValue.KEY_DOWN);
            same(slider.value, 0.223456, "numpad minus subtracts one precise step");
            inputKey(Keyboard.NUMPAD_SUBTRACT, InputValue.KEY_UP);
            same(observed.length, 5, "numpad release cannot duplicate update");
            wheel(3);
            same(slider.value, 0.323456, "positive wheel event adds one native-sized step");
            wheel(-3);
            same(slider.value, 0.223456, "negative wheel event subtracts one native-sized step");
            wheel(0);
            same(slider.value, 0.223456, "zero wheel delta cannot trigger native decrement");
            same(observed.length, 7, "wheel capture and native handler do not duplicate update");
            same(row.input.nativeStepCount, 0, "keyboard and wheel never run rounded native fallback");
            same(row.input.textField.text, "0.223456", "all step sources synchronize displayed field");
        }

        private function testClipboardCommandPassthrough():void
        {
            // Selection and copy remain native commands.
            fixture(0.123456);
            focus();
            row.input.textField.setSelection(1, 4);
            for each (var code:uint in [65, 67])
            {
                for each (var state:String in [InputValue.KEY_DOWN, InputValue.KEY_UP])
                {
                    var event:InputEvent = inputKey(code, state, null, true, true);
                    check(!event.handled && !event.isDefaultPrevented(), "Ctrl command remains native: " + code + "/" + state);
                    same(row.input.textField.selectionBeginIndex, 1, "mod preserves selection start for Ctrl command");
                    same(row.input.textField.selectionEndIndex, 4, "mod preserves selection end for Ctrl command");
                    same(row.input.textField.text, "0.123456", "mod does not rewrite text for Ctrl command");
                }
            }
            same(slider.value, 0.123456, "Ctrl commands do not change coefficient");
            same(observed.length, 0, "Ctrl commands cannot emit slider changes");
        }

        private function testClipboardCommand():void
        {
            fixture(0.5);
            focus();
            clipboardText = "0.123456";
            row.input.textField.setSelection(0, row.input.textField.text.length);
            var event:InputEvent = inputKey(Keyboard.V, InputValue.KEY_DOWN, null, true, true);
            check(event.handled && event.isDefaultPrevented(), "Ctrl+V is owned when client clipboard text is available");
            same(row.input.textField.text, "0.123456", "Ctrl+V replaces the complete selected value");
            same(slider.value, 0.123456, "Ctrl+V stages the exact pasted coefficient");
            same(observed.length, 1, "Ctrl+V emits one setting change");
        }

        private function testStageClipboardCommand():void
        {
            fixture(0.5);
            focus();
            clipboardText = "0,234567";
            row.input.textField.setSelection(0, row.input.textField.text.length);
            var event:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN,
                true, true, 0, Keyboard.V, 0, true);
            var allowed:Boolean = row.input.textField.dispatchEvent(event);
            check(!allowed && event.isDefaultPrevented(), "Stage capture owns Ctrl+V before settings input routing");
            same(row.input.textField.text, "0,234567", "Stage Ctrl+V replaces the selected field text");
            same(slider.value, 0.234567, "Stage Ctrl+V stages the exact pasted coefficient");
            same(observed.length, 1, "Stage Ctrl+V emits one setting change");
        }

        private function testHomeEndSelection():void
        {
            fixture(0.123456);
            focus();
            var field:TextField = row.input.textField;
            var nativeValue:Number = row.input.value;
            field.setSelection(3, 3);
            var home:InputEvent = inputKey(Keyboard.HOME, InputValue.KEY_DOWN, NavigationCode.HOME, true);
            check(home.handled && home.isDefaultPrevented(), "Home overrides native numeric minimum shortcut");
            same(field.selectionBeginIndex, 0, "Home places caret at first character");
            same(field.selectionEndIndex, 0, "Home clears selection");
            inputKey(Keyboard.HOME, InputValue.KEY_UP, NavigationCode.HOME, true);
            same(field.caretIndex, 0, "Home release leaves caret in place");
            inputKey(Keyboard.END, InputValue.KEY_DOWN, NavigationCode.END, true);
            same(field.selectionBeginIndex, 8, "End places caret after last character");
            same(field.selectionEndIndex, 8, "End clears selection");
            inputKey(Keyboard.END, InputValue.KEY_UP, NavigationCode.END, true);
            same(field.caretIndex, 8, "End release leaves caret in place");

            field.setSelection(3, 3);
            inputKey(Keyboard.HOME, InputValue.KEY_DOWN, NavigationCode.HOME, true, false, true);
            same(field.selectionBeginIndex, 0, "Shift+Home selects from text start");
            same(field.selectionEndIndex, 3, "Shift+Home preserves selection anchor");
            inputKey(Keyboard.END, InputValue.KEY_DOWN, NavigationCode.END, true, false, true);
            same(field.selectionBeginIndex, 3, "Shift+End retains original anchor when selection direction reverses");
            same(field.selectionEndIndex, 8, "Shift+End selects to text end");
            inputKey(Keyboard.END, InputValue.KEY_UP, NavigationCode.END, true, false, true);
            same(field.selectionBeginIndex, 3, "shifted key release preserves selection anchor");
            same(field.selectionEndIndex, 8, "shifted key release preserves selection extent");
            same(slider.value, 0.123456, "Home/End only edit selection, never coefficient");
            same(row.input.value, nativeValue, "Home/End cannot change rounded native skin value");
            same(row.input.nativeStepCount, 0, "Home/End suppress native min/max fallback on key release");
            same(observed.length, 0, "caret navigation does not dirty settings");
        }

        private function testStepperLimitsAndDisabled():void
        {
            fixture(0.2);
            slider.maxAvailableValue = 0.25;
            row.refresh();
            focus();
            check(row.input.nextBtn1.enabled, "up arrow remains available below a non-step-aligned cap");
            clickNext();
            same(slider.value, 0.25, "up arrow clamps to precise available cap");
            same(row.input.textField.text, "0.25", "display shows exact cap despite native stepper flooring");
            check(!row.input.nextBtn1.enabled, "up arrow disables at actual cap");
            var count:int = observed.length;
            clickNext();
            inputKey(Keyboard.UP, InputValue.KEY_DOWN, NavigationCode.UP);
            wheel(1);
            same(slider.value, 0.25, "all increment sources obey available cap");
            same(observed.length, count, "boundary increments do not emit unchanged settings");
            clickPrev();
            same(slider.value, 0.15, "decrement preserves offset from precise cap");
            replace("0.25");
            row.input.validateNow();
            same(slider.value, 0.25, "manual entry accepts actual cap beyond floored native maximum");
            same(row.input.textField.text, "0.25", "native redraw cannot truncate manually entered cap");
            replace("0.250001");
            same(slider.value, 0.25, "manual entry above cap is not staged");
            row.commit();
            check(row.hasInputError, "manual entry above cap reports validation error");

            fixture(0.123456);
            slider.minimum = 0.075;
            row.refresh();
            clickPrev();
            same(slider.value, 0.075, "down arrow clamps to precise minimum");
            check(!row.input.prevBtn1.enabled, "down arrow disables at actual minimum");
            count = observed.length;
            clickPrev();
            same(observed.length, count, "lower boundary cannot emit duplicate update");

            fixture(0.5);
            slider.enabled = false;
            row.refresh();
            check(!row.input.nextBtn1.enabled && !row.input.prevBtn1.enabled, "disabled slider disables both arrows");
            clickNext();
            clickPrev();
            inputKey(Keyboard.UP, InputValue.KEY_DOWN, NavigationCode.UP);
            wheel(1);
            same(slider.value, 0.5, "disabled input ignores every step source");
            same(observed.length, 0, "disabled stepping emits no settings event");
            same(row.input.nativeStepCount, 0, "disabled commands cannot fall through to native handlers");
        }

        private function testUnavailableStep():void
        {
            for each (var step:Number in [0, -0.1, NaN, Infinity])
            {
                fixture(0.5);
                slider.snapInterval = step;
                row.refresh();
                check(row.input.enabled, "invalid step does not disable manual decimal input");
                check(!row.input.nextBtn1.enabled && !row.input.prevBtn1.enabled,
                    "invalid or nonfinite step disables both arrows: " + step);
                clickNext();
                clickPrev();
                inputKey(Keyboard.UP, InputValue.KEY_DOWN, NavigationCode.UP);
                wheel(1);
                same(slider.value, 0.5, "invalid step cannot change coefficient: " + step);
                same(observed.length, 0, "invalid step cannot emit a settings event: " + step);
                same(row.input.nativeStepCount, 0, "invalid step cannot reach rounded native fallback: " + step);
                focus();
                replace("0,123456");
                same(slider.value, 0.123456, "manual decimal remains usable with unavailable step: " + step);
            }
        }

        private function testEscapeAndReset():void
        {
            fixture(0.5);
            focus();
            replace("0.123456");
            row.cancelEdit();
            same(slider.value, 0.5, "Escape restores value from focus start");
            same(row.input.textField.text, "0.5", "Escape restores displayed value");
            same(observed.length, 2, "Escape stages one restoring event");
            blur();
            same(observed.length, 2, "blur after Escape cannot recommit");
            focus();
            replace("0.123456");
            slider.value = 1;
            same(row.input.textField.text, "1", "stock Defaults slider event overrides pending edit");
            blur();
            same(slider.value, 1, "focus loss cannot revive pre-reset draft");
            focus();
            replace("0.25");
            var changes:int = observed.length;
            row.abandon();
            blur();
            same(observed.length, changes, "window cancel abandon cannot commit on focus loss");
        }

        private function testSkinAndDisposal():void
        {
            fixture(0.5);
            var old:TextField = row.input.replaceSkinField();
            focus();
            check(!replace("1e-6"), "replacement native skin field keeps paste guard");
            old.text = "1e-6";
            old.dispatchEvent(new Event(Event.CHANGE, true));
            same(row.input.textField.text, "0.5", "old native skin field listener removed");
            replace("0.25");
            same(slider.value, 0.25, "replacement field remains synchronized");
            var input:NumericStepper = row.input;
            var count:int = controls.numChildren;
            App.focused = input;
            row.dispose();
            same(slider.width, 200, "dispose restores original slider width");
            same(controls.numChildren, count - 1, "dispose removes the added field");
            check(input.wasDisposed, "dispose releases native input");
            check(App.focused == slider, "dispose moves focus to surviving native slider");
            row.dispose();
            same(slider.width, 200, "dispose is idempotent");
        }

        private function check(value:Boolean, description:String):void
        {
            assertions++;
            if (!value)
            {
                report(false, description);
                throw new Error(description);
            }
        }

        private function same(actual:*, expected:*, description:String):void
        {
            check(actual === expected, description + ": expected " + expected + ", got " + actual);
        }

        private function report(success:Boolean, message:String):void
        {
            trace((success ? "SENSITIVITY_INPUT_TESTS_PASS " : "SENSITIVITY_INPUT_TESTS_FAIL ") + message);
            if (ExternalInterface.available)
                ExternalInterface.call("betterSenseTestResult", success, message);
        }
    }
}
