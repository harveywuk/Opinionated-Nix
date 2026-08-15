// Inline calculator for the menu's search field: type an expression, a unit
// conversion, or a currency conversion and the answer appears as the top row.
//
// Everything here is pure so it can be reasoned about (and tested) without a
// running shell. Menu.qml owns the row; CalculatorService.qml owns the process.
//
// The guard below is the ONLY thing standing between a normal search and a
// nonsense answer. qalc never rejects input: `firefox` comes back as `0 B` and
// `hello world` as `6.5e-26 B²·h²·L³`, both stated as confidently as `4`. So a
// query has to earn its way to qalc rather than be refused by it.

// Words that may appear alongside digits without making the query prose.
var FUNCTION_WORDS = [
  "sqrt", "cbrt", "abs", "round", "floor", "ceil", "trunc",
  "ln", "log", "log2", "log10", "exp",
  "sin", "cos", "tan", "asin", "acos", "atan",
  "sinh", "cosh", "tanh",
  "pi", "e", "tau", "phi",
  "mod", "rem", "gcd", "lcm", "min", "max"
]

// `to`/`in`/`as` between a number-with-unit and something else: "80 usd in eur",
// "5 km to miles", "1 GiB as MB".
var CONVERSION = /(^|[\s\d)])(to|in|as)\s+\S/i
var HAS_UNIT_OPERAND = /\d\s*[a-zA-Z$€£¥₿]/

// An operator only counts when it sits between numeric context on the left and
// numeric-or-opening context on the right. Without that, the theme named
// `retro-82` reads as a subtraction and qalc answers `1 B·tr − 82`.
var INFIX = /[\d)]\s*[+\-*/^×÷]\s*[\d(.,]/
var GROUPING = /[()]/

function trim(value) {
  return String(value || "").trim()
}

// "20% of 350" is the way people say it and the one phrasing qalc cannot read —
// it answers `rem(20; 1 B)`. Both `350*20%` and `20% * 350` give 70, so say it
// the way qalc understands before anything else looks at the query.
function rewritePercentOf(query) {
  return query.replace(
    /(^|[\s(])(\d+(?:[.,]\d+)?)\s*%\s+of\s+(?=[\d(])/gi,
    "$1$2% * "
  )
}

// A comma between digits is a decimal separator here, never a thousands
// separator. qalc runs with `decimal comma 0` so that `1.5+1` is 2.5 rather
// than 16 — which is what a nl_BE locale silently returns — and this lets a
// European keyboard still type `1,5` and mean it.
function normalizeDecimalComma(query) {
  return query.replace(/(\d),(\d)/g, "$1.$2")
}

// To qalc, `in` is inches. `80 usd in eur` becomes `69.83 in × €²` — a wrong
// answer with no hint that it misread the question. Only the trailing
// `in <word>` form is rewritten, so `2 in + 3 in` keeps its inches and
// `3 in to cm` (which already says `to`) is left for qalc to read as written.
function rewriteInAsTo(query) {
  if (/(^|\s)to\s/i.test(query)) return query
  return query.replace(/\s+in\s+([A-Za-z€$£¥₿][\w/^]*)\s*$/i, " to $1")
}

var TEMPERATURE_UNITS = { F: "fahrenheit", C: "celsius", K: "kelvin" }

// To qalc `F` is farads and `C` is coulombs, so `98.6 F to C` answers
// `(98.6 C) / V`. Nobody types that in a launcher meaning capacitance. Both
// sides have to be temperature letters before they are expanded, which leaves
// a real `100 F to uF` alone, and the letters stay case-sensitive so `c` keeps
// meaning the speed of light and `k` the kilo prefix.
function rewriteTemperatureLetters(query) {
  return query.replace(
    /^(\s*[-+]?[\d.]+)\s*°?([FCK])\s+to\s+°?([FCK])\s*$/,
    function (all, amount, from, to) {
      return amount + " " + TEMPERATURE_UNITS[from] + " to " + TEMPERATURE_UNITS[to]
    }
  )
}

// Words that follow `to` as instructions rather than as a unit to convert into.
// Documented under `help to` in qalc.
var TO_KEYWORDS = [
  "base", "optimal", "prefix", "mixed", "bin", "binary", "oct", "octal",
  "duo", "duodecimal", "hex", "hexadecimal", "sexa", "sexa2", "sexa3",
  "sexagesimal", "latitude", "latitude2", "longitude", "longitude2",
  "bijective", "fp16", "fp32", "fp64", "fp80", "fp128", "bcd", "utc",
  "fraction", "factors", "partial"
]

// `to <unit>` decomposes into mixed units, so `5 km to mi` answers
// `3 mi + 188 yd + 2.393700787 in`. A `-` before the target turns that off for
// one conversion (see `help to`), which is what gives back the single number.
//
// The global `conv 0` setting does the same thing, but it also stops results
// reducing on their own — `5 N * 3 m` degrades from `15 J` to `(15 kg × m²)/s²`.
// Per-conversion keeps both behaviours.
function forceSingleUnit(query) {
  return query.replace(/(\sto\s+)([^\s-+?][^\s]*)\s*$/i, function (all, keyword, target) {
    if (TO_KEYWORDS.indexOf(target.toLowerCase()) >= 0) return all
    if (/^\d/.test(target)) return all
    // `b?MB` already asks for the optimal binary prefix; leave the hint intact.
    if (/^b\?/i.test(target)) return all
    return keyword + "-" + target
  })
}

function normalize(query) {
  var normalized = rewriteInAsTo(normalizeDecimalComma(rewritePercentOf(trim(query))))
  return forceSingleUnit(rewriteTemperatureLetters(normalized))
}

// True when every alphabetic run in the query is a known function or unit-ish
// token attached to a number. Prose fails here, which is the point.
function wordsAreAllowed(query) {
  var words = query.match(/[A-Za-z]{2,}/g)
  if (!words) return true

  for (var i = 0; i < words.length; i++) {
    var word = words[i].toLowerCase()
    if (FUNCTION_WORDS.indexOf(word) >= 0) continue
    return false
  }
  return true
}

// Decide whether `query` is worth sending to qalc at all.
function looksLikeExpression(rawQuery) {
  var query = normalize(rawQuery)

  if (query.length < 2 || query.length > 200) return false

  // A calculation involves a number, and a lone number is not a calculation.
  if (!/\d/.test(query)) return false
  if (/^\d+$/.test(query)) return false

  // Half-typed input. Answering `2+` with `2` is worse than answering nothing.
  if (/[+\-*/^(,.]$/.test(query)) return false

  // An explicit conversion carries its own units on both sides, so prose rules
  // do not apply: "80 usd in eur" is unambiguous about what it wants.
  if (CONVERSION.test(query) && HAS_UNIT_OPERAND.test(query)) return true

  if (!wordsAreAllowed(query)) return false

  return INFIX.test(query) || GROUPING.test(query) || /%/.test(query)
}

// qalc in persistent mode answers each line with:
//
//     > <the expression it read>
//     <blank>
//       <result>
//     <blank>
//
// so the result is the first non-blank line that is not the echoed prompt.
// Trim before testing. qalc ends a result block with a blank line and then
// writes its next prompt without a newline, so the split delivers the prompt as
// "\n> 80 usd to eur" — leading newline and all — for every query after the
// first. Matching "^>" against the raw chunk lets that echo through as if it
// were the answer.
function isPromptLine(line) {
  return /^>/.test(trim(line))
}

function isResultLine(line) {
  return trim(line).length > 0 && !isPromptLine(line)
}

function cleanResult(line) {
  // Strip any ANSI left over if colour ever comes back on.
  return trim(String(line || "").replace(/\[[0-9;]*m/g, ""))
}

// A result worth showing. qalc echoes the input back when it cannot do anything
// useful ("1 / 0" for `1/0`), and a row that repeats what you just typed is
// noise rather than an answer.
function isUsefulResult(result, query) {
  var answer = cleanResult(result)
  if (!answer) return false
  if (answer === trim(query)) return false
  if (answer === normalize(query)) return false
  return true
}
