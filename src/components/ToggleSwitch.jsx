export default function ToggleSwitch({ checked, onChange, disabled, label }) {
  return (
    <label className="fp-toggle" title={label}>
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange?.(e.target.checked)}
      />
      <span className="fp-toggle-track" aria-hidden="true" />
      <span className="fp-toggle-symbol fp-toggle-symbol--x" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="4"><path d="M6 6l12 12M18 6L6 18"/></svg>
      </span>
      <span className="fp-toggle-symbol fp-toggle-symbol--o" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="4"><circle cx="12" cy="12" r="7"/></svg>
      </span>
      <span className="fp-toggle-thumb" aria-hidden="true" />
    </label>
  );
}
