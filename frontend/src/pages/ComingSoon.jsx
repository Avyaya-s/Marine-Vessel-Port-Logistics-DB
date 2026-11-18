// Placeholder for pages that depend on later phases.
export default function ComingSoon({ title, phase, children }) {
  return (
    <section className="card section coming">
      <span className="coming-tag">{phase}</span>
      <h2>{title}</h2>
      <p className="muted">{children}</p>
    </section>
  )
}
