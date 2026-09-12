package
{
    import better_sense.DecimalInput;
    import flash.display.Sprite;
    import flash.external.ExternalInterface;

    /** Compile and execute this SWF to test the actual production AS3 implementation. */
    public final class DecimalInputTests extends Sprite
    {
        private var assertions:int = 0;

        public function DecimalInputTests()
        {
            testDrafts();
            testCommits();
            testSelectionAndPaste();
            testFormatting();
            trace("DECIMAL_INPUT_TESTS_PASS " + assertions);
            report(true, assertions + " assertions passed");
        }

        private function testDrafts():void
        {
            var valid:Array = ["", "0", "12", "001", "1.", "1,", "0.1", "0,1",
                               "1.123456", "1,123456", "000.000001"];
            var invalid:Array = [null, ".", ",", ".5", ",5", "1e-6", "1E3", "+1",
                                 "-1", "1-2", "1+2", "NaN", "Infinity", "1.2.3",
                                 "1,2,3", "1.2,3", "1,2.3", "1.1234567", "1,1234567",
                                 " 1", "1 ", "1 2", "1\t", "1\n", "1\r", "1\r\n",
                                 "\n1", "1\u00a0", "\u0661", "\uff11", "1\u2028"];
            var text:String;
            for each (text in valid)
            {
                check(DecimalInput.isDraft(text), "valid draft: " + text);
            }
            for each (text in invalid)
            {
                check(!DecimalInput.isDraft(text), "invalid draft: " + text);
            }
        }

        private function testCommits():void
        {
            same(DecimalInput.parse("0", 0, 10), 0, "inclusive minimum");
            same(DecimalInput.parse("10", 0, 10), 10, "inclusive maximum");
            same(DecimalInput.parse("1.123456", 0, 10), 1.123456, "six decimal places");
            same(DecimalInput.parse("1,123456", 0, 10), 1.123456, "comma decimal separator");
            same(DecimalInput.parse("0001.250000", 0, 10), 1.25, "leading and trailing zeros");
            same(DecimalInput.parse("0.000001", 0, 10), 0.000001, "smallest fractional unit");
            same(DecimalInput.parse("1", 1, 1), 1, "single-value range");
            var invalid:Array = [null, "", "1.", "1,", ".1", ",1", "1.1234567",
                                 "1e-6", "1E3", "+1", "-1", "NaN", "Infinity",
                                 "1.2,3", "1,2.3", " 1", "1 ", "1\n", "1\r", "1\t",
                                 "\uff11", "\u0661", "1\u00a0"];
            for each (var text:String in invalid)
            {
                nan(DecimalInput.parse(text, 0, 10000), "invalid commit: " + text);
            }
            nan(DecimalInput.parse("0.999999", 1, 10), "below minimum is rejected");
            nan(DecimalInput.parse("10.000001", 1, 10), "above maximum is rejected");
            nan(DecimalInput.parse("1", 2, 1), "reversed bounds");
            nan(DecimalInput.parse("1", NaN, 10), "NaN minimum");
            nan(DecimalInput.parse("1", 0, NaN), "NaN maximum");
            nan(DecimalInput.parse("1", -Infinity, 10), "infinite minimum");
            nan(DecimalInput.parse("1", 0, Infinity), "infinite maximum");
            var enormous:String = new Array(401).join("9");
            nan(DecimalInput.parse(enormous, 0, Number.MAX_VALUE), "numeric overflow");
        }

        private function testSelectionAndPaste():void
        {
            same(DecimalInput.replacement("", 0, 0, "1"), "1", "type integer");
            same(DecimalInput.replacement("1", 1, 1, "."), "1.", "type draft separator");
            same(DecimalInput.replacement("1.", 2, 2, "2"), "1.2", "complete fraction");
            same(DecimalInput.replacement("1.12345", 7, 7, "6"), "1.123456", "sixth digit");
            same(DecimalInput.replacement("1.123456", 8, 8, "7"), null, "seventh digit blocked");
            same(DecimalInput.replacement("1.123456", 7, 8, "7"), "1.123457",
                 "replace selected fractional digit at limit");
            same(DecimalInput.replacement("1.123456", 2, 8, "654321"), "1.654321",
                 "replace all selected fractional digits");
            same(DecimalInput.replacement("1.123456", 2, 8, "6543210"), null,
                 "replacement exceeding six decimal places blocked");
            same(DecimalInput.replacement("1.2", 1, 2, ","), "1,2", "replace separator");
            same(DecimalInput.replacement("1.2", 3, 3, ","), null, "second separator blocked");
            same(DecimalInput.replacement("1.2", 0, 3, "0,000001"), "0,000001",
                 "paste complete decimal over selection");
            same(DecimalInput.replacement("1.2", 0, 3, ""), "", "delete selection");
            same(DecimalInput.replacement("1.2", 1, 2, ""), "12", "delete separator");
            same(DecimalInput.replacement("1.2", 0, 1, ""), null,
                 "deletion cannot leave missing integer part");
            var pastes:Array = ["1e-6", "1E3", "+1", "-1", "NaN", "Infinity", " 1",
                                "1 ", "1\n", "1\r", "1\t", "1\u00a0", "\uff11",
                                "\u0661", "1.2,3", "1,2.3", "1.1234567"];
            for each (var paste:String in pastes)
            {
                same(DecimalInput.replacement("2", 0, 1, paste), null,
                     "invalid paste rejected whole: " + paste);
            }
            same(DecimalInput.replacement("1", 1, 1, "e-6"), null,
                 "exponent insertion cannot turn into 16");
            same(DecimalInput.replacement("1", -1, 1, "2"), null, "negative selection");
            same(DecimalInput.replacement("1", 1, 0, "2"), null, "reversed selection");
            same(DecimalInput.replacement("1", 0, 2, "2"), null, "out-of-bounds selection");
            same(DecimalInput.replacement(null, 0, 0, "2"), null, "null source");
            same(DecimalInput.replacement("1", 0, 1, null), null, "null insertion");
        }

        private function testFormatting():void
        {
            same(DecimalInput.format(0), "0", "zero");
            same(DecimalInput.format(1), "1", "integer");
            same(DecimalInput.format(1.25), "1.25", "trim decimal zeros");
            same(DecimalInput.format(0.000001), "0.000001", "no small-value exponent");
            same(DecimalInput.format(0.0000001), "0", "display below six decimal places");
            same(DecimalInput.format(-0.0000001), "0", "no negative zero");
            same(DecimalInput.format(1.2345678), "1.234568", "round to six places");
            same(DecimalInput.format(0.1 + 0.2), "0.3", "suppress floating point noise");
            same(DecimalInput.format(1e21), "1000000000000000000000", "no large-value exponent");
            var huge:String = DecimalInput.format(1.25e25);
            check(/^[0-9]+$/.test(huge) && Number(huge) == 1.25e25,
                  "large coefficient displays without exponent and preserves numeric value");
            same(DecimalInput.format(NaN), "", "no NaN display");
            same(DecimalInput.format(Infinity), "", "no positive infinity display");
            same(DecimalInput.format(-Infinity), "", "no negative infinity display");
            var precise:Number = 0.123456789;
            same(DecimalInput.format(precise), "0.123457", "display rounds precise source");
            same(precise, 0.123456789, "format does not replace source precision");
            var large:String = DecimalInput.format(Number.MAX_VALUE);
            check(large.indexOf("e") < 0 && large.indexOf("E") < 0 && large.length == 309,
                  "maximum finite Number displays without exponent");
        }

        private function check(value:Boolean, description:String):void
        {
            assertions++;
            if (!value)
            {
                trace("DECIMAL_INPUT_TESTS_FAIL " + description);
                report(false, description);
                throw new Error(description);
            }
        }

        private function report(success:Boolean, message:String):void
        {
            if (ExternalInterface.available)
            {
                ExternalInterface.call("betterSenseTestResult", success, message);
            }
        }

        private function same(actual:*, expected:*, description:String):void
        {
            check(actual === expected, description + ": expected " + expected + ", got " + actual);
        }

        private function nan(value:Number, description:String):void
        {
            check(isNaN(value), description);
        }
    }
}
