export const meta = {
  name: 'prune-read',
  description: 'Read a spec prune run\'s candidate files and return only the candidates worth proving',
  phases: [
    { title: 'Enumerate', detail: 'read back the candidate files the session listed' },
    { title: 'Assess', detail: 'one kit:spec-assessor per file' },
    { title: 'Fill', detail: 'misplaced, subsumed, over-stubbed — only while the band has room' },
  ],
}

// The reading half of /kit:prune-specs, run here so that no agent's hand-back
// reaches the session that launched it. A whole-suite run is hundreds of
// reports; delivered as hand-backs they exhaust the session before it proves
// anything, however few run at once. What returns is the collated lines only.
//
// The band is chosen here, not by the caller, because whether there is room in
// it is what decides whether each fill kind runs at all.
//
// args: { listFile, command, requestDir, cap }
//   listFile    the candidate files, one path per line, written outside the repo
//   command     the path of prune-specs.md; fill agents read their rule from it,
//               so the rule has one statement
//   requestDir  the project's request spec directory, or null where it has none
//   cap         the band's size

const CAP = args.cap || 20
const AXIS_ORDER = ['tautology', 'dead-code', 'contradiction']

const LIST = {
  type: 'object',
  properties: { files: { type: 'array', items: { type: 'string' } } },
  required: ['files'],
}

const ASSESSED = {
  type: 'object',
  properties: {
    assessed: { type: 'boolean', description: 'false if the file could not be assessed' },
    reason: { type: 'string', description: 'why not, when assessed is false' },
    lines: {
      type: 'array',
      description: 'one per line of the axis output contract; empty when nothing convicted',
      items: {
        type: 'object',
        properties: {
          line: { type: 'string', description: 'the contract line exactly as the axis writes it' },
          category: { type: 'string', enum: ['tautology', 'dead-code', 'contradiction', 'restated', 'unassessed'] },
          quoted: { type: 'string', description: 'for restated only: the declaration line and the assertion line, quoted' },
        },
        required: ['line', 'category'],
      },
    },
  },
  required: ['assessed', 'lines'],
}

const PROPOSED = {
  type: 'object',
  properties: {
    assessed: { type: 'boolean', description: 'false if the unit could not be read' },
    reason: { type: 'string' },
    candidates: { type: 'array', items: { type: 'string' }, description: 'one candidate line each, in the shape the rule names' },
  },
  required: ['assessed', 'candidates'],
}

phase('Enumerate')
const listed = await agent(
  `Read ${args.listFile} and return every non-empty line in it, in order, as files. Do not filter, normalise or add anything.`,
  { label: 'enumerate', phase: 'Enumerate', schema: LIST, effort: 'low' },
)
const files = listed ? listed.files : []
if (!files.length) {
  return { error: `no candidate files read back from ${args.listFile}` }
}

phase('Assess')
const assessed = await parallel(files.map(f => () =>
  agent(
    `Spec file: ${f}\n\nReturn each line of your output contract as one entry in lines, with its category. Set assessed to false, with the reason, if you could not assess the file.`,
    { label: `assess:${f}`, phase: 'Assess', agentType: 'kit:spec-assessor', schema: ASSESSED },
  )))

const unassessedUnits = { assess: [], misplaced: [], subsumption: [], overStubbed: [] }
const axis = []
const restated = []
const unassessedExamples = []
assessed.forEach((r, i) => {
  if (!r || !r.assessed) {
    unassessedUnits.assess.push(`${files[i]}${r && r.reason ? ` — ${r.reason}` : ' — agent failed'}`)
    return
  }
  for (const l of r.lines) {
    if (l.category === 'restated') restated.push(l)
    else if (l.category === 'unassessed') unassessedExamples.push(l.line)
    else axis.push(l)
  }
})

axis.sort((a, b) => AXIS_ORDER.indexOf(a.category) - AXIS_ORDER.indexOf(b.category))
const band = axis.slice(0, CAP).map(l => ({ kind: l.category, line: l.line }))
const beyond = axis.slice(CAP).map(l => l.line)

const dirname = p => p.replace(/\/[^/]*$/, '')
const requestPrefix = args.requestDir ? args.requestDir.replace(/\/?$/, '/') : null
const FILL = [
  {
    kind: 'misplaced',
    key: 'misplaced',
    heading: 'misplaced assertions',
    units: requestPrefix ? files.filter(f => f.startsWith(requestPrefix)) : [],
    empty: 'the scope held no request specs to propose them from',
    unit: 'request spec file',
  },
  {
    kind: 'subsumed',
    key: 'subsumption',
    heading: 'subsumption pairs',
    units: [...new Set(files.map(dirname))],
    empty: 'the scope held no spec directory',
    unit: 'spec directory (the files directly in it, not its subdirectories; return no candidates if it holds fewer than two examples)',
  },
  {
    kind: 'over-stubbed',
    key: 'overStubbed',
    heading: 'over-stubbed examples',
    units: files,
    empty: 'the scope held no spec files',
    unit: 'spec file',
  },
]

const notReached = []
for (const k of FILL) {
  const room = CAP - band.length
  if (room <= 0) {
    notReached.push(`${k.heading}: the band filled before the fill order reached them`)
    continue
  }
  if (!k.units.length) {
    notReached.push(`${k.heading}: ${k.empty}`)
    continue
  }
  phase('Fill')
  log(`${room} slots left; proposing ${k.heading} over ${k.units.length} units`)
  const proposed = await parallel(k.units.map(u => () =>
    agent(
      `Read Step 3 of ${args.command} — the paragraph on ${k.heading}, and the paragraph after them on what reading may and may not do — and apply it to this one ${k.unit}: ${u}\n\nPropose only; prove nothing and change no file. Return each candidate as one line in the shape that paragraph names. Set assessed to false, with the reason, if you could not read it.`,
      { label: `${k.key}:${u}`, phase: 'Fill', schema: PROPOSED },
    )))
  const found = []
  proposed.forEach((r, i) => {
    if (!r || !r.assessed) {
      unassessedUnits[k.key].push(`${k.units[i]}${r && r.reason ? ` — ${r.reason}` : ' — agent failed'}`)
      return
    }
    found.push(...r.candidates)
  })
  band.push(...found.slice(0, room).map(line => ({ kind: k.kind, line })))
  beyond.push(...found.slice(room))
}

return { files: files.length, band, restated, beyond, unassessedExamples, unassessedUnits, notReached }
