import { BpIcon } from './BpIcon';

interface BrandLogoProps {
  /** Show the wordmark next to the shuttlecock mark. */
  showName?: boolean;
  /** Sizing variant. */
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

/**
 * BadmintonPro brand block (the court/stadium mark + wordmark),
 * matching the locked Stitch shells.
 */
export function BrandLogo({ showName = true, size = 'md', className }: BrandLogoProps) {
  const mark = size === 'lg' ? 24 : size === 'sm' ? 14 : 18;
  return (
    <div className={`bp-brand bp-brand--${size}${className ? ` ${className}` : ''}`}>
      <span className="bp-brand__mark">
        <BpIcon name="stadium" filled size={mark} />
      </span>
      {showName ? (
        <span className="bp-brand__copy">
          <span className="bp-brand__name">BadmintonPro</span>
          <span className="bp-brand__festival">Đêm hội trăng rằm</span>
        </span>
      ) : null}
    </div>
  );
}
