package
{
    import better_sense.SensitivityInput;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.TextEvent;
    import flash.external.ExternalInterface;
    import flash.text.TextField;
    import net.wg.gui.components.controls.Slider;
    import net.wg.gui.components.controls.TextInput;
    import net.wg.gui.lobby.settings.ControlsSettings;
    import net.wg.gui.lobby.settings.vo.SettingsControlProp;
    import scaleform.clik.events.SliderEvent;

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
            testHydrationAndPrecision();
            testEditingAndSourceEvents();
            testInvalidEdits();
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
            observed = [];
            row = new SensitivityInput(controls, slider, "mouseArcadeSens", function():Boolean { return updating; });
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
            same(row.input.text, "0.123457", "initial display rounds only its text");
            same(observed.length, 0, "initial attach does not dirty settings");
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
            same(row.input.text, "0.765432", "field follows refreshed model");
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
            same(row.input.text, "0.123456", "commit canonicalizes separator");
            blur();
            same(observed.length, 1, "blur after commit does not duplicate event");
            slider.value = 0.94;
            same(slider.value, 0.9, "native slider keeps native snapping");
            same(row.input.text, "0.9", "native slider change synchronizes input");
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
            same(row.input.text, "0.5", "rollback restores native TextInput model before its handler");
            same(observed.length, 0, "raw invalid edit cannot reach stock settings");
            check(replace("1."), "incomplete decimal remains editable");
            same(slider.value, 0.5, "incomplete draft cannot change numeric source");
            row.commit();
            same(row.input.text, "0.5", "incomplete commit restores accepted value");
            check(row.input.highlight, "incomplete commit indicates rejected draft");
            check(replace("9"), "out-of-range draft remains editable");
            same(slider.value, 0.5, "out-of-range draft does not clamp or stage");
            blur();
            same(row.input.text, "0.5", "out-of-range blur restores accepted value");
            same(observed.length, 0, "invalid commit emits no stock change");
        }

        private function testEscapeAndReset():void
        {
            fixture(0.5);
            focus();
            replace("0.123456");
            row.cancelEdit();
            same(slider.value, 0.5, "Escape restores value from focus start");
            same(row.input.text, "0.5", "Escape restores displayed value");
            same(observed.length, 2, "Escape stages one restoring event");
            blur();
            same(observed.length, 2, "blur after Escape cannot recommit");
            focus();
            replace("0.123456");
            slider.value = 1;
            same(row.input.text, "1", "stock Defaults slider event overrides pending edit");
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
            same(row.input.text, "0.5", "old native skin field listener removed");
            replace("0.25");
            same(slider.value, 0.25, "replacement field remains synchronized");
            var input:TextInput = row.input;
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
