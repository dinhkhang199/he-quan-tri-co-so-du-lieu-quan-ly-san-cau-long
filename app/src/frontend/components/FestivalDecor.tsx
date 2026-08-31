interface FestivalDecorProps {
  variant?: 'page' | 'hero';
}

/**
 * Purely decorative Mid-Autumn scene shared by public, customer, manager and
 * authentication layouts. It never intercepts pointer/keyboard events.
 */
export function FestivalDecor({ variant = 'page' }: FestivalDecorProps) {
  return (
    <div className={`bp-festival bp-festival--${variant}`} aria-hidden="true">
      <span className="bp-festival__moon">
        <i className="bp-festival__crater bp-festival__crater--one" />
        <i className="bp-festival__crater bp-festival__crater--two" />
        <i className="bp-festival__crater bp-festival__crater--three" />
      </span>
      <span className="bp-festival__lantern bp-festival__lantern--left">
        <i className="bp-festival__lantern-cap" />
        <i className="bp-festival__lantern-body" />
        <i className="bp-festival__lantern-tail" />
      </span>
      <span className="bp-festival__lantern bp-festival__lantern--right">
        <i className="bp-festival__lantern-cap" />
        <i className="bp-festival__lantern-body" />
        <i className="bp-festival__lantern-tail" />
      </span>
      <span className="bp-festival__cloud bp-festival__cloud--one" />
      <span className="bp-festival__cloud bp-festival__cloud--two" />
      <span className="bp-festival__stars bp-festival__stars--one">✦</span>
      <span className="bp-festival__stars bp-festival__stars--two">✧</span>
    </div>
  );
}
