export default function SegmentedControl({ options, value, onChange, disabled }) {
  return (
    <div className={`seg-control${disabled ? ' seg-control--disabled' : ''}`}>
      {options.map((opt) => (
        <button
          key={opt.value}
          type="button"
          className={`seg-control-btn${opt.value === value ? ' seg-control-btn--active' : ''}`}
          disabled={disabled}
          onClick={() => onChange?.(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}
