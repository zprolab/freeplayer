import { useCoverArt } from '../hooks/useCoverArt';

const VARIANTS = {
  bar: { imgClass: 'cover-img', placeholderClass: 'cover-placeholder', iconSize: 18, strokeWidth: 1.5 },
  np: { imgClass: 'np-cover-img', placeholderClass: 'np-cover-placeholder', iconSize: 56, strokeWidth: 1 },
};

export default function CoverArt({
  track, variant = 'bar',
  onFetchCover, fetchingCover, coverFailReason,
}) {
  const coverUrl = useCoverArt(track);
  const v = VARIANTS[variant];

  if (coverUrl) {
    return <img src={coverUrl} alt="" className={v.imgClass} />;
  }

  const showAction = fetchingCover || !!coverFailReason;

  return (
    <div className={v.placeholderClass}>
      <svg width={v.iconSize} height={v.iconSize} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={v.strokeWidth}>
        <path d="M9 18V5l12-2v13"/>
        <circle cx="6" cy="18" r="3"/>
        <circle cx="18" cy="16" r="3"/>
      </svg>
      {onFetchCover && (
        <button
          className={`cover-fetch-btn${showAction ? ' cover-fetch-btn--active' : ''}`}
          onClick={onFetchCover}
          disabled={fetchingCover}
          title="Search iTunes for album art"
        >
          {fetchingCover ? 'Fetching…' : coverFailReason === 'no-plugin' || coverFailReason === 'plugin-error' ? 'Cover plugin unavailable' : coverFailReason ? 'No cover found' : 'Fetch Cover'}
        </button>
      )}
    </div>
  );
}
