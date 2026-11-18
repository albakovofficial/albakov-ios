# Итог прогона тестов по xcresult (этапы H и I) — один для audit.yml и ios.yml.
# Запуск: python3 ci/check-tests.py <summary.json> <tests.json>; ONLY (необязательно) — имена UI-тестов, которые должны пройти.
# Ошибка (код 1), если итогов нет (сборка или xcodebuild упали до тестов), не выполнилось ни одного теста, есть упавшие
# или пропущенные тесты (XCTSkip в тестах нет — пропуск всегда неожиданный), общий итог не Passed или тест, названный
# в ONLY, не выполнен и не прошёл (опечатка в имени).
import json, os, sys

summary, tree = sys.argv[1], sys.argv[2]
if not os.path.exists(summary) or os.path.getsize(summary) == 0:
    print('::error::Нет итогов xcresult — тесты не запускались: сборка или xcodebuild упали раньше (см. шаги выше)'); sys.exit(1)
try:
    j = json.load(open(summary))
except ValueError as e:
    print('::error::Итоги xcresult не читаются: %s' % e); sys.exit(1)
total, passed, failed = j.get('totalTestCount', 0), j.get('passedTests', 0), j.get('failedTests', 0)
skipped, result = j.get('skippedTests', 0), j.get('result', '')
print('Итог xcresult: %s; всего %d, прошло %d, упало %d, пропущено %d' % (result, total, passed, failed, skipped))
for f in j.get('testFailures', []):
    print('::error::%s: %s' % (f.get('testName', '?'), (f.get('failureText') or '')[:300]))
# прошедшие тесты по имени — из дерева tests.json
ran = set()
def walk(n):
    if n.get('nodeType') == 'Test Case' and n.get('result') == 'Passed': ran.add(n.get('name', '').split('(')[0])
    for c in n.get('children', []): walk(c)
try:
    for n in json.load(open(tree)).get('testNodes', []): walk(n)
except (OSError, ValueError) as e:
    print('::warning::Дерево тестов не читается: %s' % e)
names = [t for t in os.environ.get('ONLY', '').split() if t != 'unit']
problems = []
if total == 0: problems.append('не выполнилось ни одного теста')
if failed > 0: problems.append('упало тестов: %d' % failed)
if skipped > 0: problems.append('пропущено тестов: %d' % skipped)
if result != 'Passed': problems.append('общий итог %r вместо Passed' % result)
for t in names:
    if t not in ran: problems.append('тест %s из «only» не выполнен или не прошёл — имя с ошибкой?' % t)
if problems:
    for m in problems: print('::error::' + m)
    sys.exit(1)
