package net.wg.gui.components.controls
{
    import flash.display.Sprite;

    public final class SoundButton extends Sprite
    {
        public var enabled:Boolean = true;
        public var repeatInterval:Number = 40;
        public var repeatDelay:Number = 200;
        public var wasDisposed:Boolean = false;

        public function dispose():void { wasDisposed = true; }
    }
}
