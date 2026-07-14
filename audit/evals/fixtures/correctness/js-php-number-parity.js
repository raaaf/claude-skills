// German number parsing — client-side mirror of the canonical PHP helper.
//
// CONTRACT (must stay in parity with FormattingHelper::parseGermanNumber):
// - both separators present: the RIGHTMOST one is the decimal separator
//   ("1.234,56" -> 1234.56, "1,234.56" -> 1234.56)
// - comma only: a single comma is the decimal separator ("1234,56" -> 1234.56);
//   MULTIPLE commas are US thousands grouping ("1,234,567" -> 1234567)
// - dots only: valid German grouping OR multiple dots strip as thousands
//   ("50.000" -> 50000, "1.2.3" -> 123); any other single dot is decimal
export function parseGermanNumber(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    if (typeof value === 'number') {
        return value;
    }

    value = String(value).trim();

    if (value.indexOf('.') !== -1 && value.indexOf(',') !== -1) {
        // BUG CLASS 1: ignores separator order; US format "1,234.56"
        // becomes "1.23456" instead of 1234.56
        value = value.replace(/\./g, '').replace(',', '.');
    } else if (value.indexOf(',') !== -1) {
        // BUG CLASS 2: String.replace with a string arg replaces only the
        // FIRST comma; "1,234,567" -> "1.234,567" -> parseFloat -> 1.234
        value = value.replace(',', '.');
    } else if (/^-?[1-9]\d{0,2}(\.\d{3})+$/.test(value)) {
        // BUG CLASS 3: no fallback for multiple dots without valid grouping;
        // "1.2.3" stays unstripped -> parseFloat -> 1.2 (PHP yields 123)
        value = value.replace(/\./g, '');
    }

    const parsed = parseFloat(value);
    return isNaN(parsed) ? null : parsed;
}
