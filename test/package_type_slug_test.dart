import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/core/utils/package_type_slug.dart';

PackageModel pkg({String? type, String? slug}) => PackageModel(
      packageId: 'p1',
      name: 'Test',
      type: type,
      packageTypeSlug: slug,
      price: 100,
      isOnSale: false,
      displayOrder: 0,
      isPurchased: false,
      accessRevoked: false,
      hasTiers: false,
    );

void main() {
  group('PackageTypeSlug.derive', () {
    test('lowercases and singularises a trailing plural', () {
      // The actual production bug: the type is named "Combos".
      expect(PackageTypeSlug.derive('Combos'), 'combo');
      expect(PackageTypeSlug.derive('Combo'), 'combo');
      expect(PackageTypeSlug.derive('COMBO'), 'combo');
    });

    test('handles the standard types', () {
      expect(PackageTypeSlug.derive('Theory'), 'theory');
      expect(PackageTypeSlug.derive('Practical'), 'practical');
      expect(PackageTypeSlug.derive('Practicals'), 'practical');
    });

    test('collapses punctuation and spacing', () {
      expect(PackageTypeSlug.derive('  Theory & Notes '), 'theory-note');
    });

    test('returns null for empty input', () {
      expect(PackageTypeSlug.derive(null), isNull);
      expect(PackageTypeSlug.derive('   '), isNull);
    });
  });

  group('PackageModel.typeSlug', () {
    test('prefers the server slug over the display name', () {
      // Admin renames the type; the slug keeps clients stable.
      final p = pkg(type: 'Renamed Something', slug: 'combo');
      expect(p.typeSlug, 'combo');
      expect(p.isCombo, isTrue);
    });

    test('falls back to deriving from the name on an older backend', () {
      final p = pkg(type: 'Combos');
      expect(p.typeSlug, 'combo');
      expect(p.isCombo, isTrue);
    });

    test('the production combo package is recognised', () {
      // Exactly what /api/v1/packages returns today.
      final p = pkg(type: 'Combos', slug: 'combo');
      expect(p.isCombo, isTrue);
      expect(p.isTheory, isFalse);
      expect(p.isPractical, isFalse);
    });

    test('the old name comparison would have missed it', () {
      final p = pkg(type: 'Combos', slug: 'combo');
      expect(p.type?.toLowerCase() == 'combo', isFalse); // the bug
      expect(p.isCombo, isTrue); // the fix
    });

    test('theory and practical still resolve', () {
      expect(pkg(type: 'Theory', slug: 'theory').isTheory, isTrue);
      expect(pkg(type: 'Practical', slug: 'practical').isPractical, isTrue);
    });

    test('an unknown type matches nothing', () {
      final p = pkg(type: 'Mystery', slug: 'mystery');
      expect(p.isTheory, isFalse);
      expect(p.isPractical, isFalse);
      expect(p.isCombo, isFalse);
    });
  });

  group('the all-packages filter', () {
    const visible = {
      PackageTypeSlug.theory,
      PackageTypeSlug.practical,
      PackageTypeSlug.combo,
    };

    test('admits the combo package that used to be dropped', () {
      final packages = [
        pkg(type: 'Theory', slug: 'theory'),
        pkg(type: 'Practical', slug: 'practical'),
        pkg(type: 'Combos', slug: 'combo'),
      ];
      final shown = packages.where((p) => visible.contains(p.typeSlug)).toList();
      expect(shown.length, 3);
    });

    test('still excludes unrelated types', () {
      final packages = [
        pkg(type: 'Theory', slug: 'theory'),
        pkg(type: 'Merch', slug: 'merch'),
      ];
      final shown = packages.where((p) => visible.contains(p.typeSlug)).toList();
      expect(shown.length, 1);
    });
  });
}
