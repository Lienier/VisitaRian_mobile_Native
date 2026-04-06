'use strict';

const crypto = require('crypto');
const admin = require('firebase-admin');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

const DEFAULT_SUPER_ADMIN_EMAILS = ['reineilarayat70@gmail.com'];
const DEFAULT_INVITE_LIFETIME_HOURS = 72;
const ACCESS_ROLES = new Set(['admin', 'beneficiary']);

function getConfiguredSuperAdminEmails() {
  const configured = process.env.SUPER_ADMIN_EMAILS;
  if (!configured) {
    return new Set(DEFAULT_SUPER_ADMIN_EMAILS);
  }

  return new Set(
    configured
        .split(',')
        .map((value) => normalizeEmail(value))
        .filter((value) => value.length > 0),
  );
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function normalizeRole(value) {
  const normalized = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (!ACCESS_ROLES.has(normalized)) {
    throw new HttpsError(
        'invalid-argument',
        'Role must be either "admin" or "beneficiary".',
    );
  }
  return normalized;
}

function parseOptionalText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function parseOptionalTimestamp(value, fieldName) {
  if (value == null || value == '') {
    return null;
  }

  if (value instanceof admin.firestore.Timestamp) {
    return value;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new HttpsError(
        'invalid-argument',
        `${fieldName} must be a valid date or ISO timestamp.`,
    );
  }

  return admin.firestore.Timestamp.fromDate(date);
}

function defaultInviteExpiry() {
  return admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + DEFAULT_INVITE_LIFETIME_HOURS * 60 * 60 * 1000),
  );
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function createInviteSecret() {
  return crypto.randomBytes(24).toString('hex');
}

function parseInviteToken(token) {
  const normalized = parseOptionalText(token);
  const pieces = normalized.split('.');
  if (pieces.length !== 2 || !pieces[0] || !pieces[1]) {
    throw new HttpsError('invalid-argument', 'Invite token is invalid.');
  }

  return { inviteId: pieces[0], secret: pieces[1] };
}

function timestampToIso(value) {
  if (!(value instanceof admin.firestore.Timestamp)) {
    return null;
  }
  return value.toDate().toISOString();
}

function inviteIsExpired(inviteData) {
  const expiresAt = inviteData.expiresAt;
  return (
    expiresAt instanceof admin.firestore.Timestamp &&
    expiresAt.toMillis() <= Date.now()
  );
}

function inferStatusFromInvite(inviteData) {
  if (inviteData.revokedAt) {
    return 'revoked';
  }
  if (inviteData.redeemedAt) {
    return 'redeemed';
  }
  if (inviteIsExpired(inviteData)) {
    return 'expired';
  }
  return 'pending';
}

function inferSubscriptionStatus(subscriptionEndsAt) {
  if (!(subscriptionEndsAt instanceof admin.firestore.Timestamp)) {
    return 'active';
  }

  return subscriptionEndsAt.toMillis() > Date.now() ? 'active' : 'expired';
}

async function writeAuditLog(entry) {
  await db.collection('adminAuditLogs').add({
    ...entry,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function getAccessProfile(uid) {
  const [userRecord, adminDoc, userDoc] = await Promise.all([
    auth.getUser(uid),
    db.collection('admins').doc(uid).get(),
    db.collection('users').doc(uid).get(),
  ]);

  const claims = userRecord.customClaims || {};
  const adminData = adminDoc.exists ? adminDoc.data() || {} : {};
  const userData = userDoc.exists ? userDoc.data() || {} : {};
  const normalizedEmail = normalizeEmail(userRecord.email);
  const normalizedRole = parseOptionalText(
      claims.role || adminData.role || userData.role,
  ).toLowerCase();
  const adminStatus = parseOptionalText(adminData.status).toLowerCase();
  const isSuperAdmin =
    claims.super_admin === true ||
    normalizedRole === 'super_admin' ||
    normalizedRole === 'superadmin';
  const isAdmin =
    isSuperAdmin ||
    claims.admin === true ||
    adminStatus === 'active' ||
    normalizedRole === 'admin';

  return {
    uid,
    normalizedEmail,
    userRecord,
    claims,
    isAdmin,
    isSuperAdmin,
    role: normalizedRole,
    adminData,
    userData,
  };
}

function requireAuthenticatedUid(request) {
  const uid = request.auth && typeof request.auth.uid === 'string'
      ? request.auth.uid.trim()
      : '';

  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  return uid;
}

async function requireSuperAdmin(request) {
  const uid = requireAuthenticatedUid(request);
  const profile = await getAccessProfile(uid);
  if (!profile.isSuperAdmin) {
    throw new HttpsError(
        'permission-denied',
        'Only a super admin can perform this action.',
    );
  }
  return profile;
}

function buildInviteUrl(baseUrl, token) {
  const normalizedBaseUrl = parseOptionalText(baseUrl);
  if (!normalizedBaseUrl) {
    return null;
  }

  try {
    const url = new URL(normalizedBaseUrl);
    url.searchParams.set('invite', token);
    return url.toString();
  } catch (_) {
    throw new HttpsError(
        'invalid-argument',
        'baseUrl must be a valid absolute URL.',
    );
  }
}

function sanitizeInvite(inviteId, inviteData) {
  return {
    inviteId,
    email: inviteData.email || '',
    role: inviteData.role || '',
    organizationName: inviteData.organizationName || '',
    subscriptionLabel: inviteData.subscriptionLabel || '',
    expiresAt: timestampToIso(inviteData.expiresAt),
    subscriptionEndsAt: timestampToIso(inviteData.subscriptionEndsAt),
    status: inferStatusFromInvite(inviteData),
    redeemedByEmail: inviteData.redeemedByEmail || '',
  };
}

async function getInviteRecordFromToken(token, options = {}) {
  const { inviteId, secret } = parseInviteToken(token);
  const docRef = db.collection('adminInvites').doc(inviteId);
  const doc = await docRef.get();

  if (!doc.exists) {
    throw new HttpsError('not-found', 'Invite was not found.');
  }

  const inviteData = doc.data() || {};
  const providedSecretHash = sha256(secret);
  if (inviteData.secretHash !== providedSecretHash) {
    throw new HttpsError('permission-denied', 'Invite token is invalid.');
  }

  if (inviteData.revokedAt) {
    throw new HttpsError('failed-precondition', 'Invite has been revoked.');
  }

  if (inviteIsExpired(inviteData)) {
    throw new HttpsError('failed-precondition', 'Invite has expired.');
  }

  if (!options.allowRedeemed && inviteData.redeemedAt) {
    throw new HttpsError('failed-precondition', 'Invite has already been used.');
  }

  return {
    inviteId,
    docRef,
    inviteData,
  };
}

function mergeClaimsForRole(existingClaims, role) {
  const nextClaims = { ...existingClaims };

  delete nextClaims.beneficiary;
  delete nextClaims.admin;
  delete nextClaims.role;

  if (role === 'admin') {
    nextClaims.admin = true;
    nextClaims.role = 'admin';
  } else {
    nextClaims.beneficiary = true;
    nextClaims.role = 'beneficiary';
  }

  return nextClaims;
}

exports.bootstrapSuperAdmin = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const profile = await getAccessProfile(uid);
  const normalizedEmail = profile.normalizedEmail;
  const allowedEmails = getConfiguredSuperAdminEmails();

  const existingSuperAdmins = await db
      .collection('admins')
      .where('role', '==', 'super_admin')
      .limit(1)
      .get();

  const canBootstrap =
    profile.isSuperAdmin ||
    (
      allowedEmails.has(normalizedEmail) &&
      profile.userRecord.emailVerified === true &&
      existingSuperAdmins.empty
    );

  if (!canBootstrap) {
    throw new HttpsError(
        'permission-denied',
        'Super admin bootstrap is not allowed for this account.',
    );
  }

  await auth.setCustomUserClaims(uid, {
    ...(profile.claims || {}),
    admin: true,
    super_admin: true,
    role: 'super_admin',
  });

  await Promise.all([
    db.collection('admins').doc(uid).set({
      uid,
      email: normalizedEmail,
      role: 'super_admin',
      status: 'active',
      managedBy: 'bootstrap',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true }),
    db.collection('users').doc(uid).set({
      email: normalizedEmail,
      role: 'super_admin',
      admin: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true }),
    db.collection('accessGrants').doc(uid).set({
      uid,
      email: normalizedEmail,
      role: 'super_admin',
      status: 'active',
      subscriptionStatus: 'active',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true }),
    writeAuditLog({
      action: 'bootstrap_super_admin',
      actorUid: uid,
      actorEmail: normalizedEmail,
      targetUid: uid,
      targetEmail: normalizedEmail,
    }),
  ]);

  return {
    success: true,
    email: normalizedEmail,
    refreshRequired: true,
  };
});

exports.createAccessInvite = onCall(async (request) => {
  const actor = await requireSuperAdmin(request);
  const data = request.data || {};
  const email = normalizeEmail(data.email);
  const role = normalizeRole(data.role);
  const organizationName = parseOptionalText(data.organizationName);
  const subscriptionLabel = parseOptionalText(data.subscriptionLabel);
  const expiresAt = parseOptionalTimestamp(data.expiresAt, 'expiresAt') || defaultInviteExpiry();
  const subscriptionEndsAt = parseOptionalTimestamp(
      data.subscriptionEndsAt,
      'subscriptionEndsAt',
  );

  if (!email) {
    throw new HttpsError('invalid-argument', 'Email is required.');
  }

  const inviteRef = db.collection('adminInvites').doc();
  const inviteSecret = createInviteSecret();
  const inviteToken = `${inviteRef.id}.${inviteSecret}`;

  const invitePayload = {
    email,
    role,
    organizationName,
    subscriptionLabel,
    expiresAt,
    subscriptionEndsAt,
    secretHash: sha256(inviteSecret),
    createdByUid: actor.uid,
    createdByEmail: actor.normalizedEmail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    revokedAt: null,
    revokedByUid: null,
    redeemedAt: null,
    redeemedByUid: null,
    redeemedByEmail: null,
    status: 'pending',
  };

  await inviteRef.set(invitePayload);
  await writeAuditLog({
    action: 'create_access_invite',
    actorUid: actor.uid,
    actorEmail: actor.normalizedEmail,
    targetEmail: email,
    metadata: {
      inviteId: inviteRef.id,
      role,
      organizationName,
    },
  });

  return {
    success: true,
    inviteId: inviteRef.id,
    inviteToken,
    inviteUrl: buildInviteUrl(data.baseUrl, inviteToken),
    expiresAt: timestampToIso(expiresAt),
  };
});

exports.validateAccessInvite = onCall(async (request) => {
  const data = request.data || {};
  const invite = await getInviteRecordFromToken(data.token);
  return {
    success: true,
    invite: sanitizeInvite(invite.inviteId, invite.inviteData),
  };
});

exports.redeemAccessInvite = onCall(async (request) => {
  const uid = requireAuthenticatedUid(request);
  const inviteToken = request.data && request.data.token;
  const actor = await getAccessProfile(uid);

  if (!actor.userRecord.emailVerified) {
    throw new HttpsError(
        'failed-precondition',
        'Verify the invited email address before redeeming the invite.',
    );
  }

  const normalizedEmail = actor.normalizedEmail;
  if (!normalizedEmail) {
    throw new HttpsError(
        'failed-precondition',
        'Your account must have an email address to redeem an invite.',
    );
  }

  const { inviteId, docRef, inviteData } = await getInviteRecordFromToken(inviteToken);

  if (inviteData.email !== normalizedEmail) {
    throw new HttpsError(
        'permission-denied',
        'This invite is bound to a different email address.',
    );
  }

  if (actor.isSuperAdmin) {
    throw new HttpsError(
        'failed-precondition',
        'Super admin accounts do not use invite redemption.',
    );
  }

  const role = normalizeRole(inviteData.role);
  const subscriptionEndsAt = inviteData.subscriptionEndsAt || null;
  const subscriptionStatus = inferSubscriptionStatus(subscriptionEndsAt);
  const claims = mergeClaimsForRole(actor.claims || {}, role);

  await db.runTransaction(async (transaction) => {
    const freshSnapshot = await transaction.get(docRef);
    if (!freshSnapshot.exists) {
      throw new HttpsError('not-found', 'Invite was not found.');
    }

    const freshInvite = freshSnapshot.data() || {};

    if (freshInvite.revokedAt) {
      throw new HttpsError('failed-precondition', 'Invite has been revoked.');
    }
    if (freshInvite.redeemedAt) {
      throw new HttpsError('failed-precondition', 'Invite has already been used.');
    }
    if (inviteIsExpired(freshInvite)) {
      throw new HttpsError('failed-precondition', 'Invite has expired.');
    }
    if (freshInvite.email !== normalizedEmail) {
      throw new HttpsError(
          'permission-denied',
          'This invite is bound to a different email address.',
      );
    }

    transaction.update(docRef, {
      redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
      redeemedByUid: uid,
      redeemedByEmail: normalizedEmail,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'redeemed',
    });

    transaction.set(db.collection('accessGrants').doc(uid), {
      uid,
      email: normalizedEmail,
      role,
      organizationName: freshInvite.organizationName || '',
      subscriptionLabel: freshInvite.subscriptionLabel || '',
      subscriptionStatus,
      subscriptionStartsAt: admin.firestore.FieldValue.serverTimestamp(),
      subscriptionEndsAt,
      status: role === 'admin' ? 'active' : 'active',
      inviteId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    transaction.set(db.collection('users').doc(uid), {
      email: normalizedEmail,
      role,
      organizationName: freshInvite.organizationName || '',
      subscriptionLabel: freshInvite.subscriptionLabel || '',
      subscriptionStatus,
      subscriptionEndsAt,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    if (role === 'admin') {
      transaction.set(db.collection('admins').doc(uid), {
        uid,
        email: normalizedEmail,
        role: 'admin',
        status: 'active',
        organizationName: freshInvite.organizationName || '',
        subscriptionLabel: freshInvite.subscriptionLabel || '',
        subscriptionEndsAt,
        inviteId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  });

  await auth.setCustomUserClaims(uid, claims);
  await writeAuditLog({
    action: 'redeem_access_invite',
    actorUid: uid,
    actorEmail: normalizedEmail,
    targetUid: uid,
    targetEmail: normalizedEmail,
    metadata: {
      inviteId,
      role,
    },
  });

  return {
    success: true,
    role,
    refreshRequired: true,
  };
});

exports.revokeAccessInvite = onCall(async (request) => {
  const actor = await requireSuperAdmin(request);
  const inviteId = parseOptionalText(request.data && request.data.inviteId);

  if (!inviteId) {
    throw new HttpsError('invalid-argument', 'inviteId is required.');
  }

  const inviteRef = db.collection('adminInvites').doc(inviteId);
  const inviteSnapshot = await inviteRef.get();
  if (!inviteSnapshot.exists) {
    throw new HttpsError('not-found', 'Invite was not found.');
  }

  await inviteRef.set({
    revokedAt: admin.firestore.FieldValue.serverTimestamp(),
    revokedByUid: actor.uid,
    revokedByEmail: actor.normalizedEmail,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'revoked',
  }, { merge: true });

  await writeAuditLog({
    action: 'revoke_access_invite',
    actorUid: actor.uid,
    actorEmail: actor.normalizedEmail,
    metadata: { inviteId },
  });

  return { success: true };
});

exports.setManagedAccountStatus = onCall(async (request) => {
  const actor = await requireSuperAdmin(request);
  const targetUid = parseOptionalText(request.data && request.data.targetUid);
  const disabled = request.data && request.data.disabled === true;
  const reason = parseOptionalText(request.data && request.data.reason);

  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'targetUid is required.');
  }
  if (targetUid === actor.uid && disabled) {
    throw new HttpsError(
        'failed-precondition',
        'Super admin accounts cannot disable themselves from this action.',
    );
  }

  const targetProfile = await getAccessProfile(targetUid);
  if (targetProfile.isSuperAdmin) {
    throw new HttpsError(
        'failed-precondition',
        'Super admin accounts must be managed manually.',
    );
  }

  await auth.updateUser(targetUid, { disabled });

  await Promise.all([
    db.collection('admins').doc(targetUid).set({
      status: disabled ? 'suspended' : 'active',
      disabledReason: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      managedByUid: actor.uid,
      managedByEmail: actor.normalizedEmail,
    }, { merge: true }),
    db.collection('accessGrants').doc(targetUid).set({
      status: disabled ? 'suspended' : 'active',
      disabledReason: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      managedByUid: actor.uid,
      managedByEmail: actor.normalizedEmail,
    }, { merge: true }),
    writeAuditLog({
      action: disabled ? 'disable_managed_account' : 'enable_managed_account',
      actorUid: actor.uid,
      actorEmail: actor.normalizedEmail,
      targetUid,
      targetEmail: targetProfile.normalizedEmail,
      metadata: { reason },
    }),
  ]);

  return { success: true };
});
