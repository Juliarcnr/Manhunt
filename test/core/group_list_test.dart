import 'package:flutter_test/flutter_test.dart';
import 'package:manhunt/core/groups/group_list.dart';

void main() {
  SavedGroup g(String code, {String? name}) =>
      SavedGroup(code: code, name: name);

  group('GroupList (R-GROUPS-01, R-GROUPS-02)', () {
    test('adds in order and finds by code', () {
      final list = const GroupList().add(g('A')).add(g('B'));
      expect(list.groups.map((x) => x.code), ['A', 'B']);
      expect(list.find('B'), isNotNull);
      expect(list.find('C'), isNull);
    });

    test('at most 5 groups', () {
      var list = const GroupList();
      for (var i = 0; i < GroupList.maxGroups; i++) {
        expect(list.isFull, isFalse);
        list = list.add(g('$i'));
      }
      expect(list.isFull, isTrue);
      expect(() => list.add(g('X')), throwsA(isA<GroupLimitException>()));
    });

    test('adding a known code replaces it in place, even when full', () {
      var list = const GroupList();
      for (var i = 0; i < GroupList.maxGroups; i++) {
        list = list.add(g('$i'));
      }
      list = list.add(g('2', name: 'Crew'));
      expect(list.groups, hasLength(GroupList.maxGroups));
      expect(list.groups[2].name, 'Crew');
    });

    test('remove frees a slot', () {
      var list = const GroupList();
      for (var i = 0; i < GroupList.maxGroups; i++) {
        list = list.add(g('$i'));
      }
      list = list.remove('0');
      expect(list.isFull, isFalse);
      expect(list.add(g('X')).groups.last.code, 'X');
    });

    test('update changes only the given fields of one group', () {
      final list = const GroupList()
          .add(g('A', name: 'Old'))
          .add(g('B'))
          .update('A', groupId: 'id-a', isHost: true)
          .update('missing', name: 'ignored');
      final a = list.find('A')!;
      expect(a.name, 'Old');
      expect(a.groupId, 'id-a');
      expect(a.isHost, isTrue);
      expect(list.find('B')!.isHost, isFalse);
      expect(list.groups, hasLength(2));
    });

    test('JSON round trip', () {
      final list = const GroupList()
          .add(
            const SavedGroup(code: 'A', groupId: 'x', name: 'N', isHost: true),
          )
          .add(g('B'));
      final back = GroupList.fromJson(list.toJson());
      expect(back.groups.map((x) => x.toJson()), list.toJson());
      expect(back.find('B')!.groupId, isNull);
    });
  });
}
