package scaleform.clik.events
{
    import flash.events.Event;

    public final class ComponentEvent extends Event
    {
        public static const STATE_CHANGE:String = "stateChange";

        public function ComponentEvent(type:String)
        {
            super(type);
        }
    }
}
