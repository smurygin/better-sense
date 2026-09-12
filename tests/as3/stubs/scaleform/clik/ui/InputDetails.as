package scaleform.clik.ui
{
    public final class InputDetails
    {
        public var type:String;
        public var code:Number;
        public var value:String;
        public var navEquivalent:String;
        public var controllerIndex:uint;
        public var ctrlKey:Boolean;
        public var altKey:Boolean;
        public var shiftKey:Boolean;

        public function InputDetails(type:String, code:Number, value:String,
            navEquivalent:String = null, controllerIndex:uint = 0,
            ctrlKey:Boolean = false, altKey:Boolean = false, shiftKey:Boolean = false)
        {
            this.type = type;
            this.code = code;
            this.value = value;
            this.navEquivalent = navEquivalent;
            this.controllerIndex = controllerIndex;
            this.ctrlKey = ctrlKey;
            this.altKey = altKey;
            this.shiftKey = shiftKey;
        }
    }
}
