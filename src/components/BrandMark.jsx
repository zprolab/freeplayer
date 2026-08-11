// FreePlayer brand mark — the FP logo (F = waveform bars, P = play-button
// bowl). Source of truth: shell/logo.svg (app icon). Keep in sync visually.
// `light` renders the dark-on-light variant for light backgrounds.
export default function BrandMark({ size = 22, light = false }) {
  const fg = light ? '#1f1f23' : '#ffffff';
  return (
    <svg width={size} height={size} viewBox="0 0 128 128" fill="none" aria-hidden="true">
      <rect x="22" y="24" width="11" height="80" fill="#e24329"/>
      <rect x="37" y="28" width="36" height="11" fill={fg}/>
      <rect x="37" y="51" width="36" height="11" fill={fg}/>
      <rect x="81" y="24" width="11" height="80" fill={fg}/>
      <polygon points="98,46 98,82 124,64" fill="#e24329"/>
    </svg>
  );
}
