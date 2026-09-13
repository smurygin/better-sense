package net.wg.gui.components.controls
{
    import flash.display.Sprite;

    public final class SoundButton extends Sprite
    {
        public var enabled:Boolean = true;
        public var repeatInterval:Number = 40;
        public var repeatDelay:Number = 200;
        public var wasDisposed:Boolean = false;

        public function SoundButton()
        {
            graphics.beginFill(0);
            graphics.drawRect(0, 0, 13, 12);
            graphics.endFill();
        }

        public function dispose():void { wasDisposed = true; }
    }
}
