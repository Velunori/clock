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

function isoDay(value) {
    return value.getFullYear() + "-" + String(value.getMonth() + 1).padStart(2, "0") + "-" + String(value.getDate()).padStart(2, "0");
}
function cellDate(cell) { return new Date(cell.year, cell.month, cell.day, 12); }
function eventsForDay(events, day, calendarId) {
    return events.filter(function(event) { return event.startDay <= day && event.endDay >= day && (!calendarId || event.calendar_id === calendarId); });
}
function dayColors(events, day, calendarId) {
    var colors = [];
    eventsForDay(events, day, calendarId).forEach(function(event) { if (colors.indexOf(event.color) < 0) colors.push(event.color); });
    return colors.slice(0, 3);
}
function addDays(value, days) {
    var parts = value.split("-").map(Number);
    var original = new Date(parts[0], parts[1] - 1, parts[2], 12);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || isoDay(original) !== value) return "";
    var date = new Date(parts[0], parts[1] - 1, parts[2] + days, 12);
    return isoDay(date);
}
function localTime(value) {
    var date = new Date(value);
    return isoDay(date) + "T" + String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0");
}
