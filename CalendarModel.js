function key(date) {
    return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate();
}

function normalizedWeekStart(value) {
    var day = Number(value);
    return isFinite(day) && day >= 0 && day <= 7 ? day % 7 : 1;
}

function monthCells(year, month, weekStart, today, selected) {
    // Noon avoids local midnight transitions around daylight saving changes.
    var first = new Date(year, month, 1, 12);
    var offset = (first.getDay() - normalizedWeekStart(weekStart) + 7) % 7;
    var cells = [];
    for (var i = 0; i < 42; i++) {
        var date = new Date(year, month, 1 - offset + i, 12);
        cells.push({year: date.getFullYear(), month: date.getMonth(), day: date.getDate(),
            inMonth: date.getMonth() === month, isToday: key(date) === key(today),
            selected: key(date) === key(selected)});
    }
    return cells;
}

function shiftMonth(year, month, delta) {
    var date = new Date(year, month + delta, 1, 12);
    return {year: date.getFullYear(), month: date.getMonth()};
}
