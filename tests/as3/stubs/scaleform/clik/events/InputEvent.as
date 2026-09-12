package scaleform.clik.events
{
    import flash.events.Event;
    import scaleform.clik.ui.InputDetails;

    public final class InputEvent extends Event
    {
        public static const INPUT:String = "input";
        public var details:InputDetails;
        public var handled:Boolean = false;

        public function InputEvent(type:String, details:InputDetails, bubbles:Boolean = true, cancelable:Boolean = true)
        {
            super(type, bubbles, cancelable);
            this.details = details;
        }
    }
}
