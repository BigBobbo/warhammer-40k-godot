/**
 * parser.test.js — Tests for ArmyParser
 *
 * Run with: node server/public/js/parser.test.js
 */

const ArmyParser = require('./parser.js');

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed++;
  } else {
    failed++;
    console.error(`  FAIL: ${message}`);
  }
}

function assertEqual(actual, expected, message) {
  if (actual === expected) {
    passed++;
  } else {
    failed++;
    console.error(`  FAIL: ${message}`);
    console.error(`    Expected: ${JSON.stringify(expected)}`);
    console.error(`    Actual:   ${JSON.stringify(actual)}`);
  }
}

function test(name, fn) {
  console.log(`TEST: ${name}`);
  try {
    fn();
  } catch (err) {
    failed++;
    console.error(`  ERROR: ${err.message}`);
    console.error(`  ${err.stack}`);
  }
}

// ============================================================================
// Helper extraction tests
// ============================================================================

test('extractPoints — standard formats', () => {
  assertEqual(ArmyParser._extractPoints('Intercessor Squad (90)'), 90, 'bare number');
  assertEqual(ArmyParser._extractPoints('Intercessor Squad (90 pts)'), 90, 'pts suffix');
  assertEqual(ArmyParser._extractPoints('Intercessor Squad (90 points)'), 90, 'points suffix');
  assertEqual(ArmyParser._extractPoints('Intercessor Squad ( 90 )'), 90, 'extra spaces');
  assertEqual(ArmyParser._extractPoints('Just a name'), null, 'no points');
});

test('extractName — strips points', () => {
  assertEqual(ArmyParser._extractName('Intercessor Squad (90 pts)'), 'Intercessor Squad', 'standard');
  assertEqual(ArmyParser._extractName('Captain (80)'), 'Captain', 'bare points');
  assertEqual(ArmyParser._extractName('Just a name'), 'Just a name', 'no points');
});

test('isUnitHeader — detects unit headers', () => {
  assert(ArmyParser._isUnitHeader('Intercessor Squad (90 pts)'), 'standard unit header');
  assert(ArmyParser._isUnitHeader('Captain (80)'), 'bare points');
  assert(!ArmyParser._isUnitHeader('• Bolt rifle'), 'wargear line is not header');
  assert(!ArmyParser._isUnitHeader('Gladius Task Force'), 'plain text is not header');
});

test('isWargearLine — detects wargear lines', () => {
  assert(ArmyParser._isWargearLine('• Bolt rifle'), 'bullet');
  assert(ArmyParser._isWargearLine('· Bolt rifle'), 'middle dot');
  assert(ArmyParser._isWargearLine('- Bolt rifle'), 'dash');
  assert(ArmyParser._isWargearLine('* Bolt rifle'), 'asterisk');
  assert(ArmyParser._isWargearLine('1. Bolt rifle'), 'numbered');
  assert(ArmyParser._isWargearLine('    Bolt rifle'), 'indented');
  assert(!ArmyParser._isWargearLine('Intercessor Squad (90 pts)'), 'unit header is not wargear');
});

test('isEnhancementLine — detects enhancements', () => {
  assert(ArmyParser._isEnhancementLine('• Enhancement: Adamantine Talisman'), 'bullet enhancement');
  assert(ArmyParser._isEnhancementLine('Enhancement: Adamantine Talisman'), 'plain enhancement');
  assert(ArmyParser._isEnhancementLine('- Enhancement: Adamantine Talisman'), 'dash enhancement');
  assert(!ArmyParser._isEnhancementLine('• Bolt rifle'), 'wargear is not enhancement');
});

test('parseEnhancementLine — extracts enhancement name', () => {
  assertEqual(
    ArmyParser._parseEnhancementLine('• Enhancement: Adamantine Talisman'),
    'Adamantine Talisman',
    'bullet prefixed'
  );
  assertEqual(
    ArmyParser._parseEnhancementLine('Enhancement: Adamantine Talisman (+25 pts)'),
    'Adamantine Talisman',
    'with points'
  );
});

test('extractModelCount — gets count from name', () => {
  assertEqual(ArmyParser._extractModelCount('5 Intercessors'), 5, 'leading count');
  assertEqual(ArmyParser._extractModelCount('10 Boyz'), 10, 'larger count');
  assertEqual(ArmyParser._extractModelCount('Intercessors x5'), 5, 'trailing x-count');
  assertEqual(ArmyParser._extractModelCount('Intercessors'), null, 'no count');
});

test('parseWargearLine — cleans wargear text', () => {
  assertEqual(ArmyParser._parseWargearLine('• Bolt rifle'), 'Bolt rifle', 'bullet');
  assertEqual(ArmyParser._parseWargearLine('- Power fist'), 'Power fist', 'dash');
  assertEqual(ArmyParser._parseWargearLine('  1. Meltagun'), 'Meltagun', 'numbered');
});

// ============================================================================
// Block splitting tests
// ============================================================================

test('splitIntoBlocks — splits on blank lines', () => {
  const text = 'Line 1\nLine 2\n\nLine 3\nLine 4\n\nLine 5';
  const blocks = ArmyParser._splitIntoBlocks(text);
  assertEqual(blocks.length, 3, 'three blocks');
  assertEqual(blocks[0].length, 2, 'first block has 2 lines');
  assertEqual(blocks[1].length, 2, 'second block has 2 lines');
  assertEqual(blocks[2].length, 1, 'third block has 1 line');
});

test('splitIntoBlocks — handles multiple blank lines', () => {
  const text = 'Line 1\n\n\n\nLine 2';
  const blocks = ArmyParser._splitIntoBlocks(text);
  assertEqual(blocks.length, 2, 'two blocks');
});

// ============================================================================
// Header parsing tests
// ============================================================================

test('parseHeader — faction with points', () => {
  const result = ArmyParser._parseHeader(['Space Marines (2000 pts)']);
  assertEqual(result.faction, 'Space Marines', 'faction name');
  assertEqual(result.points, 2000, 'points');
});

test('parseHeader — faction + detachment', () => {
  const result = ArmyParser._parseHeader([
    'Space Marines (2000 pts)',
    'Gladius Task Force'
  ]);
  assertEqual(result.faction, 'Space Marines', 'faction');
  assertEqual(result.points, 2000, 'points');
  assertEqual(result.detachment, 'Gladius Task Force', 'detachment');
});

test('parseHeader — faction without points, separate points line', () => {
  const result = ArmyParser._parseHeader([
    'Space Marines',
    '2000 pts'
  ]);
  assertEqual(result.faction, 'Space Marines', 'faction');
  assertEqual(result.points, 2000, 'points from second line');
});

test('parseHeader — faction, detachment, no points', () => {
  const result = ArmyParser._parseHeader([
    'Space Marines',
    'Gladius Task Force'
  ]);
  assertEqual(result.faction, 'Space Marines', 'faction');
  assertEqual(result.detachment, 'Gladius Task Force', 'detachment');
  assertEqual(result.points, null, 'no points');
});

// ============================================================================
// Unit block parsing tests
// ============================================================================

test('parseUnitBlock — basic unit', () => {
  const unit = ArmyParser._parseUnitBlock([
    'Intercessor Squad (90 pts)'
  ]);
  assertEqual(unit.name, 'Intercessor Squad', 'name');
  assertEqual(unit.points, 90, 'points');
  assertEqual(unit.wargear.length, 0, 'no wargear');
});

test('parseUnitBlock — unit with wargear', () => {
  const unit = ArmyParser._parseUnitBlock([
    'Intercessor Squad (90 pts)',
    '• Bolt rifle',
    '• Bolt pistol',
    '• Astartes grenade launcher'
  ]);
  assertEqual(unit.name, 'Intercessor Squad', 'name');
  assertEqual(unit.points, 90, 'points');
  assertEqual(unit.wargear.length, 3, 'three wargear items');
  assertEqual(unit.wargear[0], 'Bolt rifle', 'first wargear');
  assertEqual(unit.wargear[1], 'Bolt pistol', 'second wargear');
});

test('parseUnitBlock — unit with enhancement', () => {
  const unit = ArmyParser._parseUnitBlock([
    'Captain (80 pts)',
    '• Power sword',
    '• Enhancement: Adamantine Talisman'
  ]);
  assertEqual(unit.name, 'Captain', 'name');
  assertEqual(unit.points, 80, 'points');
  assertEqual(unit.enhancement, 'Adamantine Talisman', 'enhancement');
  assertEqual(unit.wargear.length, 1, 'one wargear (enhancement excluded)');
});

test('parseUnitBlock — unit with warlord marker', () => {
  const unit = ArmyParser._parseUnitBlock([
    'Captain (80 pts)',
    'Warlord',
    '• Power sword'
  ]);
  assert(unit.isWarlord, 'isWarlord flag set');
  assertEqual(unit.wargear.length, 1, 'one wargear');
});

test('parseUnitBlock — model count in name', () => {
  const unit = ArmyParser._parseUnitBlock([
    '10 Intercessor Squad (180 pts)'
  ]);
  assertEqual(unit.name, 'Intercessor Squad', 'name without count');
  assertEqual(unit.modelCount, 10, 'model count extracted');
  assertEqual(unit.points, 180, 'points');
});

// ============================================================================
// Full parse tests — standard format
// ============================================================================

test('parse — standard army list', () => {
  const text = `Space Marines (2000 pts)
Gladius Task Force

Intercessor Squad (90 pts)
• Bolt rifle
• Bolt pistol

Bladeguard Veterans (100 pts)
• Master-crafted power sword
• Storm shield

Captain (80 pts)
• Power sword
• Enhancement: Adamantine Talisman
Warlord`;

  const result = ArmyParser.parse(text);
  assertEqual(result.faction, 'Space Marines', 'faction');
  assertEqual(result.detachment, 'Gladius Task Force', 'detachment');
  assertEqual(result.points, 2000, 'points');
  assertEqual(result.units.length, 3, 'three units');
  assertEqual(result.format, 'standard', 'format');

  assertEqual(result.units[0].name, 'Intercessor Squad', 'first unit name');
  assertEqual(result.units[0].points, 90, 'first unit points');
  assertEqual(result.units[0].wargear.length, 2, 'first unit wargear count');

  assertEqual(result.units[1].name, 'Bladeguard Veterans', 'second unit name');
  assertEqual(result.units[1].points, 100, 'second unit points');

  assertEqual(result.units[2].name, 'Captain', 'third unit name');
  assertEqual(result.units[2].enhancement, 'Adamantine Talisman', 'captain enhancement');
  assert(result.units[2].isWarlord, 'captain is warlord');
});

test('parse — army list without header points', () => {
  const text = `Orks
Waaagh! Tribe

Boyz (90 pts)
• Slugga
• Choppa

Warboss (70 pts)
• Power klaw`;

  const result = ArmyParser.parse(text);
  assertEqual(result.faction, 'Orks', 'faction');
  assertEqual(result.detachment, 'Waaagh! Tribe', 'detachment');
  assertEqual(result.points, 160, 'summed points');
  assertEqual(result.units.length, 2, 'two units');
});

test('parse — army list with minimal header', () => {
  const text = `Adeptus Custodes

Custodian Guard (150 pts)
• Guardian spear

Shield-Captain (120 pts)
• Castellan axe`;

  const result = ArmyParser.parse(text);
  assertEqual(result.faction, 'Adeptus Custodes', 'faction');
  assertEqual(result.units.length, 2, 'two units');
  assertEqual(result.points, 270, 'summed points');
});

test('parse — empty input', () => {
  const result = ArmyParser.parse('');
  assertEqual(result.units.length, 0, 'no units');
  assert(result.errors.length > 0, 'has errors');
});

test('parse — null input', () => {
  const result = ArmyParser.parse(null);
  assertEqual(result.units.length, 0, 'no units');
  assert(result.errors.length > 0, 'has errors');
});

// ============================================================================
// BattleScribe format tests
// ============================================================================

test('parse — BattleScribe format', () => {
  const text = `++ Army Roster (Space Marines) [2000 pts] ++
++ Configuration ++
++ HQ ++
Captain [80 pts]
. Power sword
. Bolt pistol
++ Troops ++
Intercessor Squad [90 pts]
. Bolt rifle`;

  const result = ArmyParser.parse(text);
  assertEqual(result.format, 'battlescribe', 'format detected');
  assertEqual(result.units.length, 2, 'two units');
  assertEqual(result.units[0].name, 'Captain', 'first unit');
  assertEqual(result.units[0].points, 80, 'captain points');
  assertEqual(result.units[1].name, 'Intercessor Squad', 'second unit');
});

test('detectFormat — standard vs battlescribe', () => {
  assertEqual(ArmyParser.detectFormat('Space Marines (2000)'), 'standard', 'standard');
  assertEqual(ArmyParser.detectFormat('++ Army ++'), 'battlescribe', 'battlescribe');
});

// ============================================================================
// Edge cases
// ============================================================================

test('parse — Windows line endings', () => {
  const text = "Space Marines (1000 pts)\r\nGladius Task Force\r\n\r\nIntercessor Squad (90 pts)\r\n• Bolt rifle";
  const result = ArmyParser.parse(text);
  assertEqual(result.units.length, 1, 'parsed correctly');
  assertEqual(result.units[0].name, 'Intercessor Squad', 'unit name');
});

test('parse — extra blank lines', () => {
  const text = `Space Marines (1000 pts)
Gladius Task Force



Intercessor Squad (90 pts)
• Bolt rifle



Captain (80 pts)
• Power sword`;

  const result = ArmyParser.parse(text);
  assertEqual(result.units.length, 2, 'two units despite extra blanks');
});

test('parse — wargear with various bullet styles', () => {
  const text = `Space Marines
Test Detachment

Test Unit (100 pts)
• Bullet wargear
· Middle dot wargear
- Dash wargear
* Asterisk wargear`;

  const result = ArmyParser.parse(text);
  assertEqual(result.units[0].wargear.length, 4, 'all 4 wargear items parsed');
});

// ============================================================================
// Results
// ============================================================================

console.log('\n' + '='.repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);
console.log('='.repeat(50));

if (failed > 0) {
  process.exit(1);
} else {
  console.log('All tests passed!');
}
