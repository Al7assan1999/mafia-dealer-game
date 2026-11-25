// [QA] Sprint 5: chat (send / ack / fail / retry / queue / unread / no duplicates / swipe in both directions /
// reactions / edits and their limit / mentions / out players), block and report, the admin queue, and the
// walkthrough fixes (day roster, how the town decides, host controls during a drop, lobby summary, guide, handles).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_dealer/core/auth.dart';
import 'package:mafia_dealer/features/offline/offline_game.dart';
import 'package:mafia_dealer/core/ui.dart';

import 'driver.dart';
import 'fake_server.dart';
import 'harness.dart';
import 'online_test.dart' show FakeRoom, connOf, frames, member, openRoom, roomMsg, view;

Map<String, Object?> chatMsg(int id, int from, String text, {int to = -1, int? at, Map<String, Object?>? extra}) =>
    {'id': id, 'from': from, 'to': to, 'text': text, 'at': at ?? DateTime.now().millisecondsSinceEpoch, ...?extra};

Future<FakeRoom> lobbyWithChat(WidgetTester t, {String lang = 'en', List<Map<String, Object?>> history = const []}) async {
  final r = (await openRoom(t, lang: lang)).room;
  r.last.push(roomMsg(1));
  r.last.push({'t': 'view', 'rev': 1, 'view': null});
  r.last.push({'t': 'chatAll', 'msgs': history});
  await frames(t);
  return r;
}

List<Map<String, Object?>> sentOf(FakeRoom r, String t) => [for (final s in r.socks) ...s.msgs.where((m) => m['t'] == t)];

void main() {
  setUpAll(setUpHarness);

  group('chat', () {
    testWidgets('unread badge; send shows "sending" until confirmed; a refused one can be retried; no duplicates after history', (t) async {
      final r = await lobbyWithChat(t);
      r.last.push({'t': 'chat', 'msg': chatMsg(1, 2, 'hi all')});
      await frames(t);
      expect(connOf(t).unreadTotal, 1);
      await tapKey(t, 'chat');
      await frames(t);
      expect(connOf(t).unreadTotal, 0, reason: 'opening the conversation reads it');
      expect(find.text('hi all'), findsOneWidget);
      await t.enterText(find.byKey(const Key('chatText')), 'hello');
      await tapKey(t, 'chatSend');
      final sent = sentOf(r, 'chat').last;
      expect(sent['text'], 'hello');
      expect(find.text('Sending…'), findsOneWidget);
      r.last.push({'t': 'chat', 'msg': chatMsg(2, 1, 'hello'), 'cid': sent['cid']});
      await frames(t);
      expect(find.text('Sending…'), findsNothing);
      expect(find.text('hello'), findsOneWidget);
      // refused (slow down): "not sent", a tap resends it
      await t.enterText(find.byKey(const Key('chatText')), 'too fast');
      await tapKey(t, 'chatSend');
      r.last.push({'t': 'err', 'error': 'slow', 'ref': sentOf(r, 'chat').last['cid']});
      await frames(t);
      expect(find.text('Not sent · tap to retry'), findsOneWidget);
      await t.tap(find.text('too fast'));
      await frames(t);
      expect(sentOf(r, 'chat').where((m) => m['text'] == 'too fast'), hasLength(2));
      // the history again (a rejoin): nothing doubles
      r.last.push({'t': 'chatAll', 'msgs': [chatMsg(1, 2, 'hi all'), chatMsg(2, 1, 'hello')]});
      await frames(t);
      expect(find.text('hi all'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('written during a drop: goes out after reconnecting', (t) async {
      final r = await lobbyWithChat(t);
      await tapKey(t, 'chat');
      r.last.drop();
      await frames(t);
      await t.enterText(find.byKey(const Key('chatText')), 'are you there?');
      await tapKey(t, 'chatSend');
      expect(sentOf(r, 'chat'), isEmpty);
      await t.pump(const Duration(seconds: 2));
      expect(r.socks.length, 2);
      expect(r.last.msgs.where((m) => m['t'] == 'chat').single['text'], 'are you there?');
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('reply by swiping toward the middle ($lang)', (t) async {
        await lobbyWithChat(t, lang: lang, history: [chatMsg(5, 2, 'who is lying?')]);
        await tapKey(t, 'chat');
        await frames(t);
        await t.fling(find.byKey(const Key('msg_5')), Offset(lang == 'ar' ? -300 : 300, 0), 1500);
        await frames(t);
        expect(find.textContaining('P2: who is lying?'), findsOneWidget, reason: 'the reply bar');
      });
    }

    testWidgets('long press: react; edit my message within 15 minutes, not after; mention a player', (t) async {
      final old = DateTime.now().millisecondsSinceEpoch - 16 * 60 * 1000;
      final r = await lobbyWithChat(t, history: [chatMsg(1, 2, 'theirs'), chatMsg(2, 1, 'mine new'), chatMsg(3, 1, 'mine old', at: old)]);
      await tapKey(t, 'chat');
      await frames(t);
      await t.longPress(find.byKey(const Key('msg_1')));
      await frames(t);
      await tapKey(t, 'rx_4');
      expect(sentOf(r, 'react').last, {'t': 'react', 'id': 1, 'rx': 4});
      await t.longPress(find.byKey(const Key('msg_3')));
      await frames(t);
      expect(find.byKey(const Key('menuEdit')), findsNothing, reason: 'older than 15 minutes');
      await t.tapAt(const Offset(200, 40));
      await frames(t);
      await t.longPress(find.byKey(const Key('msg_2')));
      await frames(t);
      await tapKey(t, 'menuEdit');
      await t.enterText(find.byKey(const Key('chatText')), 'mine edited');
      await tapKey(t, 'chatSend');
      expect(sentOf(r, 'edit').last, {'t': 'edit', 'id': 2, 'text': 'mine edited'});
      // [S13-3] typing "@" in the box offers the players; "@P" narrows it; a tap puts "@P2 " in
      await t.enterText(find.byKey(const Key('chatText')), '@P');
      await frames(t, 2);
      expect(find.byKey(const Key('mentionList')), findsOneWidget);
      await tapKey(t, 'mention_2');
      expect(t.widget<TextField>(find.byKey(const Key('chatText'))).controller!.text, '@P2 ');
      await t.enterText(find.byKey(const Key('chatText')), '${t.widget<TextField>(find.byKey(const Key('chatText'))).controller!.text}vote now');
      await tapKey(t, 'chatSend');
      expect(sentOf(r, 'chat').last['mentions'], [2]);
    });

    testWidgets('out of the game: the "out players only" note on Everyone', (t) async {
      final r = (await openRoom(t)).room;
      r.last.push(roomMsg(1, status: 'game'));
      r.last.push(view(1, 'day', extra: {'alive': false, 'ph': 'dead'}));
      await frames(t);
      await tapKey(t, 'chat');
      await frames(t);
      expect(find.byKey(const Key('outOnly')), findsOneWidget);
    });
  });

  group('safety', () {
    testWidgets('report a chat message (with "also block"): the server gets the room, the message and the block', (t) async {
      final o = await openRoom(t);
      o.room.last.push(roomMsg(1));
      o.room.last.push({'t': 'view', 'rev': 1, 'view': null});
      o.room.last.push({'t': 'chatAll', 'msgs': [chatMsg(7, 2, 'you are all idiots')]});
      await frames(t);
      await tapKey(t, 'chat');
      await frames(t);
      await t.longPress(find.byKey(const Key('msg_7')));
      await frames(t);
      await tapKey(t, 'menuReport');
      expect(find.text('you are all idiots'), findsWidgets, reason: 'the message is shown in the report');
      expect(t.widget<TextButton>(find.byKey(const Key('sendReport'))).onPressed, isNull, reason: 'no reason chosen yet (S6-5)');
      await tapKey(t, 'reason_hate');
      await tapKey(t, 'sendReport');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await frames(t);
      expect(o.server.reports.single, containsPair('msgId', 7));
      expect(o.server.reports.single, containsPair('room', '123456'));
      expect(o.server.reports.single, containsPair('reason', 'hate'));
      expect(o.server.blocks.any((b) => b.$2 == 'u1'), isTrue, reason: '"also block" was on');
    });

    testWidgets('the admin queue: only for the admin; ban removes the report; blocked list unblocks', (t) async {
      final s = FakeServer(), tok = s.user('Boss');
      s.user('Spammer');
      s.admin = s.idOf('Boss');
      s.reports.add({'id': 'r1', 'userId': s.idOf('Spammer'), 'by': s.idOf('Boss'), 'reason': 'spam'});
      s.blocks.add((s.idOf('Boss'), s.idOf('Spammer')));
      await launch(t, server: s, tokens: MemoryTokens()..t = tok);
      await frames(t, 8);
      await tapKey(t, 'profile');
      await t.scrollUntilVisible(find.byKey(const Key('reports')), 300, scrollable: find.byType(Scrollable).first);
      await tapKey(t, 'reports');
      await frames(t, 8);
      expect(find.textContaining('Spammer'), findsWidgets);
      await tapKey(t, 'ban_r1');
      await t.tap(find.text('Ban').last);
      await frames(t, 8);
      expect(s.reports, isEmpty);
      expect(s.users[s.idOf('Spammer')]!['banned'], true);
      await t.binding.handlePopRoute();
      await frames(t, 5);
      await t.scrollUntilVisible(find.byKey(const Key('blockedList')), 300, scrollable: find.byType(Scrollable).first);
      await tapKey(t, 'blockedList');
      await frames(t, 8);
      await tapKey(t, 'unblock_Spammer');
      await frames(t, 8);
      expect(s.blocks, isEmpty);
    });
  });

  group('walkthrough fixes', () {
    testWidgets('online: the host can\'t act during a drop; the lobby says what is dealt and who is offline; the day shows who is in', (t) async {
      final r = (await openRoom(t)).room;
      r.last.push(roomMsg(1, members: [member(0, host: true), member(1), member(2), member(3, online: false)]));
      r.last.push({'t': 'view', 'rev': 1, 'view': null});
      await frames(t);
      expect(t.widget<Text>(find.byKey(const Key('dealSummary'))).data, '4 players · Classic · 1 Mafia · Doctor');
      expect(find.text('P4 is offline and would be dealt in'), findsOneWidget);
      r.last.push(roomMsg(2, status: 'game'));
      r.last.push(view(2, 'day', extra: {'timer': {'left': 100}, 'roster': [{'name': 'P1', 'alive': true}, {'name': 'P2', 'alive': false}, {'name': 'P3', 'alive': true}, {'name': 'P4', 'alive': true}]}));
      await frames(t);
      expect(find.text('P2 · out'), findsOneWidget);
      expect(find.text('Secret vote (each phone)'), findsOneWidget);
      r.refuse = true;
      r.last.drop();
      await t.pump(const Duration(seconds: 4));
      final before = r.socks.expand((x) => x.msgs).length;
      await t.tap(find.byKey(const Key('secretVote')), warnIfMissed: false);
      await frames(t);
      expect(r.socks.expand((x) => x.msgs).length, before, reason: 'nothing queued from a host control during a drop');
    });

    testWidgets('offline: who is in on the day screen; "decide together" opens the pick list and goes back', (t) async {
      await launch(t);
      await setUpGame(t, ['Dareer', 'Halawy', 'Farouq', 'Sami', 'Hokan']);
      for (var i = 0; i < 200 && gameOf(t).screen != Screen.day; i++) {
        final g = gameOf(t);
        switch (g.screen) {
          case Screen.dealCard:
            final hold = await t.startGesture(t.getCenter(find.byKey(const Key('roleCard'))));
            await t.pump(const Duration(milliseconds: 100));
            await hold.up();
            await t.pump();
            await tapKey(t, 'memorized');
          case Screen.nightPick:
            final no = g.view(g.who).night!;
            if (no.key != 'none') await tapKey(t, 'opt_${no.opts.firstWhere((o) => !o.disabled).seat}');
            await tapKey(t, 'confirm');
          case Screen.nightLocked: await tapKey(t, 'nightNext');
          case Screen.dawn: await tapKey(t, 'dawn');
          case Screen.morning: await tapKey(t, g.revealed ? 'startDay' : 'revealNow');
          case Screen.end: return;
          default: await tapKey(t, 'open');
        }
      }
      for (var i = 0; i < 5; i++) { expect(find.byKey(Key('roster_$i')), findsOneWidget); }
      expect(find.byKey(const Key('decide')), findsNothing, reason: 'one way at a time');
      await tapKey(t, 'decideTogether');
      expect(find.byKey(const Key('decide')), findsOneWidget);
      await tapKey(t, 'decideBack');
      expect(find.byKey(const Key('ballot')), findsOneWidget);
    });

    testWidgets('first launch offers How to play once; Arabic handles stay "@name"', (t) async {
      final s = FakeServer(), tok = s.user('Sami');
      final app = await launch(t, server: s, tokens: MemoryTokens()..t = tok);
      await frames(t, 5);
      expect(find.byKey(const Key('openGuide')), findsOneWidget);
      await tapKey(t, 'openGuide');
      await tapKey(t, 'guideDone');
      await frames(t, 5);
      expect(find.byKey(const Key('openGuide')), findsNothing);
      expect(app.prefs.guideSeen, isTrue);
      expect(find.byKey(const Key('howToPlay')), findsOneWidget, reason: 'still reachable from Home');
      expect(atHandle('Sami'), '\u2066@Sami\u2069');
      expect(find.text(atHandle('Sami')), findsOneWidget); // [S15-1] the @handle next to the avatar again
    });
  });
}
