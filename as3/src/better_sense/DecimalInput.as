package better_sense
{
    /** Decimal text rules shared by keyboard entry, paste, and commit. */
    public final class DecimalInput
    {
        private static const DRAFT:RegExp = /^[0-9]+(?:[.,][0-9]{0,6})?$/;
        private static const COMPLETE:RegExp = /^[0-9]+(?:[.,][0-9]{1,6})?$/;

        public static function isDraft(text:String):Boolean
        {
            return text != null && (text.length == 0 || matchesEntirely(DRAFT, text));
        }

        /** Returns NaN for incomplete text, non-finite bounds, or an out-of-range value. */
        public static function parse(text:String, minimum:Number, maximum:Number):Number
        {
            if (text == null || !matchesEntirely(COMPLETE, text) ||
                !isFinite(minimum) || !isFinite(maximum) || minimum > maximum)
            {
                return NaN;
            }

            var value:Number = Number(text.replace(",", "."));
            return isFinite(value) && value >= minimum && value <= maximum ? value : NaN;
        }

        /** Display rounding only: callers must keep the original numeric source value. */
        public static function format(value:Number):String
        {
            if (!isFinite(value))
            {
                return "";
            }

            var text:String = value.toFixed(6);
            if (text.indexOf("e") >= 0 || text.indexOf("E") >= 0)
            {
                text = expandExponent(text);
            }

            if (text.indexOf(".") >= 0)
            {
                text = text.replace(/0+$/, "").replace(/\.$/, "");
            }
            return text == "-0" ? "0" : text;
        }

        /** Validates the complete edit; invalid pasted text is never sanitized. */
        public static function replacement(text:String, start:int, end:int,
                                           insertion:String):String
        {
            if (text == null || insertion == null || start < 0 || end < start ||
                end > text.length)
            {
                return null;
            }

            var result:String = text.substring(0, start) + insertion + text.substring(end);
            return isDraft(result) ? result : null;
        }

        private static function matchesEntirely(pattern:RegExp, text:String):Boolean
        {
            // The $ anchor alone can also match before a terminal line break.
            var match:Object = pattern.exec(text);
            return match != null && match[0] == text;
        }

        private static function expandExponent(text:String):String
        {
            var parts:Array = text.toLowerCase().split("e");
            var coefficient:String = parts[0];
            var exponent:int = int(parts[1]);
            var sign:String = "";
            if (coefficient.charAt(0) == "-")
            {
                sign = "-";
                coefficient = coefficient.substring(1);
            }

            var point:int = coefficient.indexOf(".");
            if (point < 0)
            {
                point = coefficient.length;
            }
            var digits:String = coefficient.replace(".", "");
            point += exponent;

            if (point <= 0)
            {
                return sign + "0." + zeros(-point) + digits;
            }
            if (point >= digits.length)
            {
                return sign + digits + zeros(point - digits.length);
            }
            return sign + digits.substring(0, point) + "." + digits.substring(point);
        }

        private static function zeros(count:int):String
        {
            var result:String = "";
            while (count-- > 0)
            {
                result += "0";
            }
            return result;
        }
    }
}
