// Security rule tests. Run via: firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  writeBatch,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const GID = 'g1';
const inDays = (d) => new Date(Date.now() + d * 24 * 3600 * 1000);
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'manhunt-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  // Seed: admin's lobby with admin + member "kim".
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'games', GID), {
      adminUid: 'admin',
      status: 'lobby',
      settings: 'enc',
      startAt: null,
      createdAt: new Date(),
      expiresAt: inDays(180),
    });
    for (const uid of ['admin', 'kim']) {
      await setDoc(doc(db, 'games', GID, 'members', uid), {
        name: 'enc',
        role: 'unassigned',
        caught: false,
        jokerUsed: false,
        joinedAt: new Date(),
      });
    }
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// Running round: admin is hunter, kim and sam are players.
const startRound = () =>
  env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, 'games', GID), { status: 'running' });
    await updateDoc(doc(db, 'games', GID, 'members', 'admin'), { role: 'hunter' });
    await updateDoc(doc(db, 'games', GID, 'members', 'kim'), { role: 'player' });
    await setDoc(doc(db, 'games', GID, 'members', 'sam'), {
      name: 'enc', role: 'player', caught: false, jokerUsed: false, joinedAt: new Date(),
    });
  });
const newMember = () => ({
  name: 'enc',
  role: 'unassigned',
  caught: false,
  jokerUsed: false,
  joinedAt: serverTimestamp(),
});

describe('games', () => {
  test('signed-in user can get a game by id (needed to join)', async () => {
    await assertSucceeds(getDoc(doc(as('stranger'), 'games', GID)));
  });

  test('not signed in → no access', async () => {
    await assertFails(getDoc(doc(anon(), 'games', GID)));
  });

  test('games cannot be listed (ids stay secret)', async () => {
    await assertFails(getDocs(collection(as('kim'), 'games')));
  });

  test('create only as own admin and in lobby', async () => {
    const game = {
      adminUid: 'x',
      status: 'lobby',
      settings: 'enc',
      startAt: null,
      createdAt: serverTimestamp(),
      expiresAt: new Date(),
    };
    await assertSucceeds(setDoc(doc(as('x'), 'games', 'g2'), game));
    await assertFails(setDoc(doc(as('y'), 'games', 'g3'), game));
    await assertFails(setDoc(doc(as('x'), 'games', 'g4'), { ...game, status: 'running' }));
    await assertFails(setDoc(doc(as('x'), 'games', 'g5'), { ...game, extra: 1 }));
  });

  test('only admin can update/start/delete', async () => {
    await assertFails(updateDoc(doc(as('kim'), 'games', GID), { status: 'running' }));
    await assertSucceeds(updateDoc(doc(as('admin'), 'games', GID), { status: 'running' }));
    await assertFails(updateDoc(doc(as('admin'), 'games', GID), { adminUid: 'kim' }));
    await assertFails(deleteDoc(doc(as('kim'), 'games', GID)));
    await assertSucceeds(deleteDoc(doc(as('admin'), 'games', GID)));
  });
});

describe('members', () => {
  test('members can list members, strangers cannot', async () => {
    await assertSucceeds(getDocs(collection(as('kim'), 'games', GID, 'members')));
    await assertFails(getDocs(collection(as('stranger'), 'games', GID, 'members')));
  });

  test('a user may read their own (missing) member doc before joining', async () => {
    await assertSucceeds(getDoc(doc(as('new'), 'games', GID, 'members', 'new')));
    await assertFails(getDoc(doc(as('new'), 'games', GID, 'members', 'kim')));
  });

  test('join: only own doc, unassigned, not caught', async () => {
    await assertSucceeds(setDoc(doc(as('new'), 'games', GID, 'members', 'new'), newMember()));
    await assertFails(setDoc(doc(as('new'), 'games', GID, 'members', 'other'), newMember()));
    await assertFails(
      setDoc(doc(as('new2'), 'games', GID, 'members', 'new2'), { ...newMember(), role: 'hunter' }),
    );
  });

  test('cannot join a missing game', async () => {
    await assertFails(setDoc(doc(as('new'), 'games', 'nope', 'members', 'new'), newMember()));
  });

  test('joining a running game is allowed (lost phone)', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'games', GID), { status: 'running' }),
    );
    await assertSucceeds(setDoc(doc(as('new'), 'games', GID, 'members', 'new'), newMember()));
  });

  test('roles: only admin, only the role field', async () => {
    await assertSucceeds(updateDoc(doc(as('admin'), 'games', GID, 'members', 'kim'), { role: 'hunter' }));
    await assertFails(updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), { role: 'player' }));
    await assertFails(updateDoc(doc(as('admin'), 'games', GID, 'members', 'kim'), { role: 'boss' }));
  });

  test('users may rename only themselves', async () => {
    await assertSucceeds(updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), { name: 'enc2' }));
    await assertFails(updateDoc(doc(as('kim'), 'games', GID, 'members', 'admin'), { name: 'x' }));
  });

  test('leave yourself or be removed by admin', async () => {
    await assertFails(deleteDoc(doc(as('kim'), 'games', GID, 'members', 'admin')));
    await assertSucceeds(deleteDoc(doc(as('admin'), 'games', GID, 'members', 'kim')));
    await assertSucceeds(deleteDoc(doc(as('admin'), 'games', GID, 'members', 'admin')));
  });
});

describe('rounds & cleanup', () => {
  const seedRoundData = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const name of ['pings', 'hunterLocs', 'events', 'speedhuntTargets']) {
        await setDoc(doc(db, 'games', GID, name, 'd1'), { data: 'enc' });
      }
    });
  const expire = () =>
    env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'games', GID), { expiresAt: inDays(-1) }),
    );

  test('status can only be lobby or running', async () => {
    await assertFails(updateDoc(doc(as('admin'), 'games', GID), { status: 'ended' }));
    await assertSucceeds(
      updateDoc(doc(as('admin'), 'games', GID), { status: 'lobby', expiresAt: inDays(180) }),
    );
  });

  test('host resets caught/joker at round end, others cannot set them', async () => {
    await assertSucceeds(
      updateDoc(doc(as('admin'), 'games', GID, 'members', 'kim'), { caught: false, jokerUsed: false }),
    );
    await assertFails(updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), { jokerUsed: true }));
  });

  test('round data: host deletes, others cannot', async () => {
    await seedRoundData();
    await assertSucceeds(getDocs(collection(as('kim'), 'games', GID, 'events')));
    await assertFails(getDocs(collection(as('stranger'), 'games', GID, 'events')));
    await assertFails(deleteDoc(doc(as('kim'), 'games', GID, 'pings', 'd1')));
    for (const name of ['pings', 'hunterLocs', 'events', 'speedhuntTargets']) {
      await assertSucceeds(deleteDoc(doc(as('admin'), 'games', GID, name, 'd1')));
    }
  });

  test('unknown subcollections stay closed', async () => {
    await assertFails(getDocs(collection(as('kim'), 'games', GID, 'secrets')));
  });

  test('active group: members cannot delete it or others', async () => {
    await assertFails(deleteDoc(doc(as('kim'), 'games', GID, 'members', 'admin')));
    await assertFails(deleteDoc(doc(as('kim'), 'games', GID)));
  });

  test('expired group (90 days): any member may delete everything', async () => {
    await seedRoundData();
    await expire();
    await assertSucceeds(deleteDoc(doc(as('kim'), 'games', GID, 'pings', 'd1')));
    await assertSucceeds(deleteDoc(doc(as('kim'), 'games', GID, 'members', 'admin')));
    await assertSucceeds(deleteDoc(doc(as('kim'), 'games', GID, 'members', 'kim')));
    await assertSucceeds(deleteDoc(doc(as('kim'), 'games', GID)));
  });
});

describe('catches & history', () => {
  const catchEvent = () => ({ type: 'catch', createdAt: serverTimestamp(), data: 'enc' });
  const summary = () => ({ endedAt: new Date(), data: 'enc' });

  test('members may report catches during a round, strangers not', async () => {
    await startRound();
    await assertSucceeds(setDoc(doc(as('kim'), 'games', GID, 'events', 'e1'), catchEvent()));
    await assertFails(setDoc(doc(as('stranger'), 'games', GID, 'events', 'e2'), catchEvent()));
  });

  test('players cannot create speedhunts; no extra fields', async () => {
    await startRound();
    await assertFails(
      setDoc(doc(as('kim'), 'games', GID, 'events', 'e3'), { ...catchEvent(), type: 'speedhunt' }),
    );
    await assertFails(
      setDoc(doc(as('kim'), 'games', GID, 'events', 'e4'), { ...catchEvent(), player: 'kim' }),
    );
  });

  test('host writes round summaries, members read them', async () => {
    await assertSucceeds(setDoc(doc(as('admin'), 'games', GID, 'history', 'r1'), summary()));
    await assertFails(setDoc(doc(as('kim'), 'games', GID, 'history', 'r2'), summary()));
    await assertSucceeds(getDocs(collection(as('kim'), 'games', GID, 'history')));
    await assertFails(getDocs(collection(as('stranger'), 'games', GID, 'history')));
  });

  test('history cannot be edited; only host deletes it', async () => {
    await assertSucceeds(setDoc(doc(as('admin'), 'games', GID, 'history', 'r1'), summary()));
    await assertFails(updateDoc(doc(as('admin'), 'games', GID, 'history', 'r1'), { data: 'x' }));
    await assertFails(deleteDoc(doc(as('kim'), 'games', GID, 'history', 'r1')));
    await assertSucceeds(deleteDoc(doc(as('admin'), 'games', GID, 'history', 'r1')));
  });
});

describe('lifetime (R-PRIV-05)', () => {
  test('any member may extend the lifetime by opening the group', async () => {
    await assertSucceeds(updateDoc(doc(as('kim'), 'games', GID), { expiresAt: inDays(180) }));
  });

  test('…but not beyond 180 days, and nothing else', async () => {
    await assertFails(updateDoc(doc(as('kim'), 'games', GID), { expiresAt: inDays(400) }));
    await assertFails(updateDoc(doc(as('admin'), 'games', GID), { expiresAt: inDays(400) }));
    await assertFails(
      updateDoc(doc(as('kim'), 'games', GID), { expiresAt: inDays(180), status: 'running' }),
    );
  });

  test('strangers cannot extend', async () => {
    await assertFails(updateDoc(doc(as('stranger'), 'games', GID), { expiresAt: inDays(180) }));
  });
});

describe('play area (R-SET-10)', () => {
  test('any member may edit the area in the lobby', async () => {
    await assertSucceeds(
      updateDoc(doc(as('kim'), 'games', GID), { area: 'enc-area', expiresAt: inDays(180) }),
    );
  });

  test('…but not during a running round', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'games', GID), { status: 'running' }),
    );
    await assertFails(updateDoc(doc(as('kim'), 'games', GID), { area: 'enc-area' }));
  });

  test('members still cannot touch the other settings', async () => {
    await assertFails(
      updateDoc(doc(as('kim'), 'games', GID), { area: 'enc-area', settings: 'x' }),
    );
    await assertFails(updateDoc(doc(as('stranger'), 'games', GID), { area: 'enc-area' }));
  });

  test('area must be ciphertext (string)', async () => {
    await assertFails(updateDoc(doc(as('kim'), 'games', GID), { area: [1, 2] }));
  });
});

describe('running round (phase 5)', () => {
  const ping = (uid, slot = 'regular_1', extra = {}) => ({
    uid, kind: 'regular', slot, createdAt: serverTimestamp(), data: 'enc', ...extra,
  });
  const pingDoc = (db, uid, slot = 'regular_1') => doc(db, 'games', GID, 'pings', `${uid}_${slot}`);
  const hunterLoc = () => ({ updatedAt: serverTimestamp(), data: 'enc' });

  beforeEach(startRound);

  describe('pings (R-PING-01, R-HUNT-03, R-PLAY-01)', () => {
    test('players send their own pings', async () => {
      await assertSucceeds(setDoc(pingDoc(as('kim'), 'kim'), ping('kim')));
    });

    test('no pings for others, by hunters, or with wrong id', async () => {
      await assertFails(setDoc(pingDoc(as('kim'), 'sam'), ping('sam')));
      await assertFails(setDoc(pingDoc(as('admin'), 'admin'), ping('admin')));
      await assertFails(setDoc(doc(as('kim'), 'games', GID, 'pings', 'random'), ping('kim')));
    });

    test('pings cannot be changed afterwards', async () => {
      await assertSucceeds(setDoc(pingDoc(as('kim'), 'kim'), ping('kim')));
      await assertFails(setDoc(pingDoc(as('kim'), 'kim'), ping('kim', 'regular_1', { data: 'fake' })));
    });

    test('no pings outside a running round', async () => {
      await env.withSecurityRulesDisabled((ctx) =>
        updateDoc(doc(ctx.firestore(), 'games', GID), { status: 'lobby' }),
      );
      await assertFails(setDoc(pingDoc(as('kim'), 'kim'), ping('kim')));
    });

    test('hunters read all pings; players only their own', async () => {
      await assertSucceeds(setDoc(pingDoc(as('kim'), 'kim'), ping('kim')));
      await assertSucceeds(setDoc(pingDoc(as('sam'), 'sam'), ping('sam')));
      await assertSucceeds(getDocs(collection(as('admin'), 'games', GID, 'pings')));
      await assertSucceeds(
        getDocs(query(collection(as('kim'), 'games', GID, 'pings'), where('uid', '==', 'kim'))),
      );
      await assertFails(getDocs(collection(as('kim'), 'games', GID, 'pings')));
      await assertFails(getDoc(pingDoc(as('kim'), 'sam')));
    });
  });

  describe('hunter positions & joker (R-HUNT-02, R-PLAY-02)', () => {
    test('hunters share their own position; players cannot read it', async () => {
      await assertSucceeds(setDoc(doc(as('admin'), 'games', GID, 'hunterLocs', 'admin'), hunterLoc()));
      await assertFails(setDoc(doc(as('admin'), 'games', GID, 'hunterLocs', 'kim'), hunterLoc()));
      await assertFails(setDoc(doc(as('kim'), 'games', GID, 'hunterLocs', 'kim'), hunterLoc()));
      await assertSucceeds(getDocs(collection(as('admin'), 'games', GID, 'hunterLocs')));
      await assertFails(getDocs(collection(as('kim'), 'games', GID, 'hunterLocs')));
    });

    test('joker: once, then hunter positions are readable for a moment', async () => {
      const me = doc(as('kim'), 'games', GID, 'members', 'kim');
      await assertSucceeds(updateDoc(me, { jokerUsed: true, jokerAt: serverTimestamp() }));
      await assertSucceeds(getDocs(collection(as('kim'), 'games', GID, 'hunterLocs')));
      // Second joker is not possible.
      await assertFails(updateDoc(me, { jokerUsed: true, jokerAt: serverTimestamp() }));
    });

    test('joker time cannot be faked', async () => {
      await assertFails(
        updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), {
          jokerUsed: true, jokerAt: inDays(1),
        }),
      );
    });

    test('old joker no longer opens hunter positions', async () => {
      await env.withSecurityRulesDisabled((ctx) =>
        updateDoc(doc(ctx.firestore(), 'games', GID, 'members', 'kim'), {
          jokerUsed: true, jokerAt: new Date(Date.now() - 5 * 60 * 1000),
        }),
      );
      await assertFails(getDocs(collection(as('kim'), 'games', GID, 'hunterLocs')));
    });
  });

  describe('catch (R-CATCH-01)', () => {
    test('a hunter marks a player as caught', async () => {
      await assertSucceeds(updateDoc(doc(as('admin'), 'games', GID, 'members', 'kim'), { caught: true }));
    });

    test('a player marks themself, but not others', async () => {
      await assertSucceeds(updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), { caught: true }));
      await assertFails(updateDoc(doc(as('kim'), 'games', GID, 'members', 'sam'), { caught: true }));
    });

    test('hunters cannot be caught; nobody un-catches', async () => {
      await assertFails(updateDoc(doc(as('kim'), 'games', GID, 'members', 'admin'), { caught: true }));
      await assertSucceeds(updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), { caught: true }));
      await assertFails(updateDoc(doc(as('kim'), 'games', GID, 'members', 'kim'), { caught: false }));
      await assertFails(updateDoc(doc(as('sam'), 'games', GID, 'members', 'kim'), { caught: false }));
    });
  });

  describe('speedhunt (R-SPEED-02, R-SPEED-04)', () => {
    const event = () => ({ type: 'speedhunt', createdAt: serverTimestamp(), data: 'enc' });
    const target = (uid) => ({ uid, createdAt: serverTimestamp() });

    test('hunters start speedhunts; players cannot', async () => {
      await assertSucceeds(setDoc(doc(as('admin'), 'games', GID, 'events', 's1'), event()));
      await assertSucceeds(setDoc(doc(as('admin'), 'games', GID, 'speedhuntTargets', 's1'), target('kim')));
      await assertFails(setDoc(doc(as('kim'), 'games', GID, 'events', 's2'), event()));
      await assertFails(setDoc(doc(as('kim'), 'games', GID, 'speedhuntTargets', 's2'), target('sam')));
    });

    test('only hunters and the target see who is targeted', async () => {
      await assertSucceeds(setDoc(doc(as('admin'), 'games', GID, 'speedhuntTargets', 's1'), target('kim')));
      await assertSucceeds(getDoc(doc(as('kim'), 'games', GID, 'speedhuntTargets', 's1')));
      await assertSucceeds(getDoc(doc(as('admin'), 'games', GID, 'speedhuntTargets', 's1')));
      await assertFails(getDoc(doc(as('sam'), 'games', GID, 'speedhuntTargets', 's1')));
      await assertFails(getDocs(collection(as('sam'), 'games', GID, 'speedhuntTargets')));
      await assertSucceeds(
        getDocs(query(collection(as('sam'), 'games', GID, 'speedhuntTargets'), where('uid', '==', 'sam'))),
      );
    });
  });
});

describe('player joker (R-PLAY-03)', () => {
  beforeEach(startRound);

  const useJoker = (uid, requestId = 'r1') => {
    const db = as(uid);
    const batch = writeBatch(db);
    batch.update(doc(db, 'games', GID, 'members', uid), {
      playerJokerUsed: true, playerJokerAt: serverTimestamp(),
    });
    batch.set(doc(db, 'games', GID, 'jokerRequests', requestId), {
      uid, createdAt: serverTimestamp(),
    });
    return batch.commit();
  };
  const answer = (uid, requestId = 'r1', requester = 'kim', extra = {}) =>
    setDoc(doc(as(uid), 'games', GID, 'jokerAnswers', `${requestId}_${uid}`), {
      request: requestId, requester, uid, createdAt: serverTimestamp(), data: 'enc', ...extra,
    });

  test('a player asks once (request only together with using the joker)', async () => {
    await assertSucceeds(useJoker('kim'));
    await assertFails(useJoker('kim', 'r2'));
    await assertFails(
      setDoc(doc(as('sam'), 'games', GID, 'jokerRequests', 'r3'), {
        uid: 'sam', createdAt: serverTimestamp(),
      }),
    );
  });

  test('hunters cannot use it or see requests', async () => {
    await assertFails(useJoker('admin'));
    await assertSucceeds(useJoker('kim'));
    await assertFails(getDocs(collection(as('admin'), 'games', GID, 'jokerRequests')));
    await assertSucceeds(getDocs(collection(as('sam'), 'games', GID, 'jokerRequests')));
  });

  test('other players answer; only the requester reads the answers', async () => {
    await assertSucceeds(useJoker('kim'));
    await assertSucceeds(answer('sam'));
    await assertSucceeds(getDoc(doc(as('kim'), 'games', GID, 'jokerAnswers', 'r1_sam')));
    await assertFails(getDoc(doc(as('admin'), 'games', GID, 'jokerAnswers', 'r1_sam')));
    await assertFails(getDoc(doc(as('sam'), 'games', GID, 'jokerAnswers', 'r1_sam')));
    await assertSucceeds(
      getDocs(query(collection(as('kim'), 'games', GID, 'jokerAnswers'), where('requester', '==', 'kim'))),
    );
    await assertFails(getDocs(collection(as('admin'), 'games', GID, 'jokerAnswers')));
  });

  test('no answers for others, to unknown requests, or by hunters', async () => {
    await assertSucceeds(useJoker('kim'));
    await assertFails(answer('admin'));
    await assertFails(answer('sam', 'nope'));
    await assertFails(answer('sam', 'r1', 'admin')); // wrong requester
    await assertFails(
      setDoc(doc(as('sam'), 'games', GID, 'jokerAnswers', 'r1_kim'), {
        request: 'r1', requester: 'kim', uid: 'kim', createdAt: serverTimestamp(), data: 'enc',
      }),
    );
  });

  test('host resets the player joker at round end', async () => {
    await assertSucceeds(useJoker('kim'));
    await assertSucceeds(
      updateDoc(doc(as('admin'), 'games', GID, 'members', 'kim'), { playerJokerUsed: false }),
    );
  });
});

// Regression: deleting a group / ending a round lists every round collection
// before deleting. This failed with "permission denied" for a host who was
// not a hunter (bug found in the first field test, 2026-10-05).
describe('clean-up flows list before deleting', () => {
  const ROUND = ['pings', 'hunterLocs', 'events', 'speedhuntTargets', 'jokerRequests', 'jokerAnswers'];

  const seed = () =>
    env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const name of ROUND) {
        await setDoc(doc(db, 'games', GID, name, 'd1'), {
          uid: 'kim', requester: 'kim', data: 'enc',
        });
      }
    });

  const listAndDeleteAll = async (uid) => {
    const db = as(uid);
    for (const name of ROUND) {
      const snap = await getDocs(collection(db, 'games', GID, name));
      for (const d of snap.docs) await deleteDoc(d.ref);
    }
  };

  const setHostRole = (role) =>
    env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'games', GID, 'members', 'admin'), { role }),
    );

  for (const role of ['unassigned', 'player', 'hunter']) {
    test(`host (${role}) can clean up in the lobby`, async () => {
      await setHostRole(role);
      await seed();
      await assertSucceeds(listAndDeleteAll('admin'));
    });
  }

  test('host who is a player cannot read round data while it runs', async () => {
    await startRound();
    await setHostRole('player');
    await seed();
    await assertFails(getDocs(collection(as('admin'), 'games', GID, 'pings')));
    await assertFails(getDocs(collection(as('admin'), 'games', GID, 'jokerAnswers')));
  });

  test('host stops the round first, then cleans up', async () => {
    await startRound();
    await setHostRole('player');
    await seed();
    await assertSucceeds(
      updateDoc(doc(as('admin'), 'games', GID), { status: 'lobby', expiresAt: inDays(180) }),
    );
    await assertSucceeds(listAndDeleteAll('admin'));
  });

  test('normal members never read others\' round data in the lobby', async () => {
    await seed();
    await assertFails(getDocs(collection(as('kim'), 'games', GID, 'pings')));
  });

  test('after expiry any member can clean up everything', async () => {
    await seed();
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'games', GID), { expiresAt: inDays(-1) }),
    );
    await assertSucceeds(listAndDeleteAll('kim'));
  });

  test('deleting the whole group as host works end to end', async () => {
    await setHostRole('player');
    await seed();
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'games', GID, 'history', 'h1'), { endedAt: new Date(), data: 'enc' }),
    );
    const db = as('admin');
    await assertSucceeds(listAndDeleteAll('admin'));
    for (const d of (await getDocs(collection(db, 'games', GID, 'history'))).docs) {
      await assertSucceeds(deleteDoc(d.ref));
    }
    await assertSucceeds(deleteDoc(doc(db, 'games', GID, 'members', 'kim')));
    await assertSucceeds(deleteDoc(doc(db, 'games', GID, 'members', 'admin')));
    await assertSucceeds(deleteDoc(doc(db, 'games', GID)));
  });
});
