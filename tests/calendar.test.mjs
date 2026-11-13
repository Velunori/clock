import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const model = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('../CalendarModel.js', import.meta.url), 'utf8'), model);
const today = new Date(2026, 10, 12, 12);

test('Monday and Sunday first grids include adjacent months in order', () => {
    for (const start of [0, 1, 7]) {
        const cells = model.monthCells(2026, 10, start, today, today);
        assert.equal(cells.length, 42);
        assert.equal(new Date(cells[0].year, cells[0].month, cells[0].day, 12).getDay(), start % 7);
        assert.equal(cells.filter(day => day.inMonth).length, 30);
        assert.equal(cells.filter(day => day.isToday).length, 1);
        assert.equal(cells.find(day => day.selected).day, 12);
    }
});

test('leap year and year boundaries are correct', () => {
    assert.equal(model.monthCells(2024, 1, 1, today, today).filter(day => day.inMonth).length, 29);
    assert.equal(model.monthCells(2025, 1, 1, today, today).filter(day => day.inMonth).length, 28);
    assert.equal(JSON.stringify(model.shiftMonth(2026, 11, 1)), JSON.stringify({year: 2027, month: 0}));
    assert.equal(JSON.stringify(model.shiftMonth(2026, 0, -1)), JSON.stringify({year: 2025, month: 11}));
});

test('DST month cells have consecutive local calendar dates', () => {
    for (const month of [2, 9]) {
        const cells = model.monthCells(2026, month, 1, today, today);
        for (let i = 1; i < cells.length; i++) {
            const before = cells[i - 1], after = cells[i];
            const next = new Date(before.year, before.month, before.day + 1, 12);
            assert.equal(model.key(next), model.key(new Date(after.year, after.month, after.day, 12)));
        }
    }
});


test('agenda spans days and source filters also control marker colors', () => {
    const events = [
        {startDay:'2026-11-12',endDay:'2026-11-13',calendar_id:'a',color:'#123456'},
        {startDay:'2026-11-13',endDay:'2026-11-13',calendar_id:'b',color:'#abcdef'},
        {startDay:'2026-11-13',endDay:'2026-11-13',calendar_id:'a',color:'#123456'}
    ];
    assert.equal(model.eventsForDay(events,'2026-11-12','').length,1);
    assert.equal(model.eventsForDay(events,'2026-11-13','a').length,2);
    assert.equal(model.eventsForDay(events,'2026-11-14','').length,0);
    assert.equal(JSON.stringify(model.dayColors(events,'2026-11-13','')),JSON.stringify(['#123456','#abcdef']));
    assert.equal(model.addDays('2026-12-31',1),'2027-01-01');
    assert.equal(model.addDays('2026-02-30',1),'');
});
