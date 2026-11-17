"""Dansk tekstforberedelse til talesyntese: tal, årstal, klokkeslæt, datoer, enheder og forkortelser
skrives ud, som de siges. Prototype i Python; skal porteres til Swift i appen."""
import re

UNITS = ["nul", "en", "to", "tre", "fire", "fem", "seks", "syv", "otte", "ni", "ti", "elleve", "tolv", "tretten",
         "fjorten", "femten", "seksten", "sytten", "atten", "nitten"]
TENS = {20: "tyve", 30: "tredive", 40: "fyrre", 50: "halvtreds", 60: "tres", 70: "halvfjerds", 80: "firs", 90: "halvfems"}
ORDINALS = {1: "første", 2: "anden", 3: "tredje", 4: "fjerde", 5: "femte", 6: "sjette", 7: "syvende", 8: "ottende",
            9: "niende", 10: "tiende", 11: "ellevte", 12: "tolvte", 13: "trettende", 14: "fjortende", 15: "femtende",
            16: "sekstende", 17: "syttende", 18: "attende", 19: "nittende", 20: "tyvende", 30: "tredivte"}
MONTHS = "januar|februar|marts|april|maj|juni|juli|august|september|oktober|november|december"


def below_100(n, neuter=False):
    if n < 20:
        return "et" if (n == 1 and neuter) else UNITS[n]
    unit, ten = n % 10, n - n % 10
    return TENS[ten] if unit == 0 else f"{UNITS[unit]}og{TENS[ten]}"


def below_1000(n, neuter=False):
    hundreds, rest = divmod(n, 100)
    parts = []
    if hundreds:
        parts.append("hundrede" if hundreds == 1 else f"{UNITS[hundreds]} hundrede")
    if rest:
        if parts:
            parts.append("og")
        parts.append(below_100(rest, neuter))
    return " ".join(parts)


def cardinal(n, neuter=False):
    """1250 -> 'tusind to hundrede og halvtreds'. neuter=True giver 'et' for 1 (et år, et hundrede)."""
    if n == 0:
        return "nul"
    if n < 0:
        return "minus " + cardinal(-n, neuter)
    parts = []
    billions, n = divmod(n, 10**9)
    millions, n = divmod(n, 10**6)
    thousands, rest = divmod(n, 1000)
    if billions:
        parts.append("en milliard" if billions == 1 else f"{cardinal(billions)} milliarder")
    if millions:
        parts.append("en million" if millions == 1 else f"{cardinal(millions)} millioner")
    if thousands:
        parts.append("tusind" if thousands == 1 else f"{below_1000(thousands, neuter=True)} tusind")
    if rest:
        if parts and rest < 100:
            parts.append("og")
        parts.append(below_1000(rest, neuter))
    return " ".join(parts)


def ordinal(n):
    if n in ORDINALS:
        return ORDINALS[n]
    if n < 100:
        unit, ten = n % 10, n - n % 10
        tens_ord = {20: "tyvende", 30: "tredivte", 40: "fyrretyvende", 50: "halvtredsindstyvende", 60: "tresindstyvende",
                    70: "halvfjerdsindstyvende", 80: "firsindstyvende", 90: "halvfemsindstyvende"}[ten]
        return tens_ord if unit == 0 else f"{UNITS[unit]}og{tens_ord}"
    return cardinal(n) + "ende"


def year(n):
    """1999 -> 'nitten hundrede og nioghalvfems', 2026 -> 'to tusind og seksogtyve'."""
    if 1100 <= n <= 1999:
        century, rest = divmod(n, 100)
        return f"{UNITS[century]} hundrede" + (f" og {below_100(rest)}" if rest else "")
    return cardinal(n)


def decimal(whole, frac):
    frac_words = below_100(int(frac)) if len(frac) <= 2 and not frac.startswith("0") else " ".join(UNITS[int(d)] for d in frac)
    return f"{cardinal(int(whole))} komma {frac_words}"


ABBREVIATIONS = [
    (r"\bbl\.\s?a\.", "blandt andet"), (r"\bf\.\s?eks\.", "for eksempel"), (r"\bfx\b", "for eksempel"),
    (r"\bca\.", "cirka"), (r"\bdvs\.", "det vil sige"), (r"\bosv\.", "og så videre"), (r"\bm\.v\.", "med videre"),
    (r"\bmv\.", "med videre"), (r"\bm\.fl\.", "med flere"), (r"\bpga\.", "på grund af"), (r"\bevt\.", "eventuelt"),
    (r"\bnr\.", "nummer"), (r"\btlf\.", "telefon"), (r"\bmio\.", "millioner"), (r"\bmia\.", "milliarder"),
    (r"\bkl\.", "klokken"), (r"\bkr\.", "kroner"), (r"\bjf\.", "jævnfør"), (r"\bhhv\.", "henholdsvis"),
    (r"\binkl\.", "inklusive"), (r"\bekskl\.", "eksklusive"), (r"\bmin\.(?=\s+\d|\s*$)", "minutter"),
    (r"\bst\.", "sankt"), (r"\bdr\.", "doktor"), (r"\bmht\.", "med hensyn til"), (r"\bift\.", "i forhold til"),
    (r"\bmfl\.", "med flere"), (r"\bo\.lign\.", "og lignende"), (r"\bvha\.", "ved hjælp af"),
]
UNITS_AFTER_NUMBER = [
    (r"%", "procent"), (r"km/t", "kilometer i timen"), (r"km", "kilometer"), (r"kg", "kilo"), (r"cm", "centimeter"),
    (r"mm", "millimeter"), (r"m²|m2", "kvadratmeter"), (r"°C", "grader"), (r"°", "grader"), (r"kr", "kroner"),
    (r"g", "gram"), (r"m", "meter"), (r"l", "liter"), (r"t", "timer"),
]
NUM = r"\d{1,3}(?:\.\d{3})+|\d+"


def to_int(s):
    return int(s.replace(".", ""))


def normalize(text):
    text = re.sub(r"\s+", " ", text).strip()
    text = text.replace("&", " og ").replace("§", "paragraf ")
    for pattern, spoken in ABBREVIATIONS:
        text = re.sub(pattern, spoken, text, flags=re.IGNORECASE)

    # Klokkeslæt: "klokken 14.30" / "14:30"
    def clock(m):
        h, mi = int(m.group(2)), int(m.group(3))
        return f"{m.group(1)}{cardinal(h)}" + ("" if mi == 0 else f" {'nul ' if mi < 10 else ''}{below_100(mi)}")
    text = re.sub(r"(klokken )(\d{1,2})[.:](\d{2})\b", clock, text)
    text = re.sub(r"()\b([01]?\d|2[0-3]):([0-5]\d)\b", clock, text)

    # Datoer: "3. maj", "den 21. juni 2026", "d. 3/5"
    text = re.sub(r"\bd\.\s?(?=\d)", "den ", text)
    text = re.sub(rf"\b(\d{{1,2}})\.\s?({MONTHS})\b", lambda m: f"{ordinal(int(m.group(1)))} {m.group(2)}", text, flags=re.IGNORECASE)
    text = re.sub(r"\bden (\d{1,2})\.(?!\d)", lambda m: f"den {ordinal(int(m.group(1)))}", text)

    # Årstal: fire cifre 1100–2099 uden tusindtalsseparator, når konteksten ligner et årstal
    year_context = rf"(?:\b(?:i|år|året|fra|siden|til|før|efter|omkring|{MONTHS})\s)"
    text = re.sub(rf"({year_context})(1[1-9]\d\d|20\d\d)\b(?![.,]\d)", lambda m: m.group(1) + year(int(m.group(2))), text, flags=re.IGNORECASE)

    # Kroner og øre: "249,95 kr" / "kr 249,95"
    text = re.sub(rf"({NUM}),(\d{{2}})\s?(?:kroner|kr)\b", lambda m: f"{cardinal(to_int(m.group(1)))} kroner og {below_100(int(m.group(2)))}", text)

    # Tal med enhed
    for unit, spoken in UNITS_AFTER_NUMBER:
        text = re.sub(rf"((?:{NUM})(?:,\d+)?)\s?{unit}(?![\wæøå])", lambda m, s=spoken: f"{m.group(1)} {s}", text)

    # Decimaltal og heltal. "et" foran intetkønsord kan ikke afgøres generelt; fælleskøn bruges.
    text = re.sub(rf"({NUM}),(\d+)", lambda m: decimal(str(to_int(m.group(1))), m.group(2)), text)
    text = re.sub(rf"(?<![\w]){NUM}(?![\w])", lambda m: cardinal(to_int(m.group(0))), text)
    text = re.sub(r"\d", lambda m: f" {UNITS[int(m.group(0))]} ", text)  # resterende cifre, fx i "A4"

    text = re.sub(r"\s+", " ", text).strip()
    return text if text and text[-1] in ".!?" else text + "."


if __name__ == "__main__":
    for s in ["Der blev givet støtte til 1.250 elever i 2026.", "Mødet er kl. 14.30 d. 3. maj.", "Prisen er 249,95 kr. inkl. moms.",
              "Ca. 3,5 % af de 2.500.000 borgere, bl.a. børn.", "Han blev født i 1999 og løb 21 km på 1 time.", "Den 21. er der 100 pladser."]:
        print(normalize(s))
