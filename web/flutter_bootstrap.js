{{flutter_js}}
{{flutter_build_config}}
// CanvasKit needs WebGL for its normal accelerated path. Some mobile browsers
// (or devices with graphics acceleration disabled) expose Flutter's semantics
// tree but fail to paint the canvas, which looks like unstyled HTML. Detect
// WebGL before startup and use CanvasKit's CPU path only on those devices.
const mindtrackCanvas = document.createElement('canvas');
const mindtrackHasWebGL = Boolean(
  mindtrackCanvas.getContext('webgl2') || mindtrackCanvas.getContext('webgl'),
);
_flutter.loader.load({
  config: { canvasKitForceCpuOnly: !mindtrackHasWebGL },
});
