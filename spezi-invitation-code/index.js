//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

const admin = require("firebase-admin");
const {https} = require("firebase-functions/v2");
const {FieldValue} = require("firebase-admin/firestore");

class InvitationCodeVerifier {
  constructor(firestore, invitationCodePath = "invitationCodes", userPath = "users") {
    this.firestore = firestore;
    this.invitationCodePath = invitationCodePath;
    this.userPath = userPath;
  }

  async enrollUserInStudy(userId, invitationCode) {
    if (!userId || typeof userId !== 'string') {
      throw new https.HttpsError(
        "invalid-argument",
        "The function must be called with a valid 'userId'.",
      );
    }

    if (!invitationCode || typeof invitationCode !== 'string') {
      throw new https.HttpsError(
        "invalid-argument",
        "The function must be called with a valid 'invitationCode'.",
      );
    }

    const invitationCodeRef = this.firestore.doc(`${this.invitationCodePath}/${invitationCode}`);
    const invitationCodeDoc = await invitationCodeRef.get();

    if (!invitationCodeDoc.exists || invitationCodeDoc.data().used) {
      throw new https.HttpsError("not-found", "Invitation code not found or already used.");
    }

    const userStudyRef = this.firestore.doc(`${this.userPath}/${userId}`);
    const userStudyDoc = await userStudyRef.get();

    if (userStudyDoc.exists) {
      throw new https.HttpsError("already-exists", "User is already enrolled in the study.");
    }

    await this.firestore.runTransaction(async (transaction) => {
      transaction.set(userStudyRef, {
        invitationCode: invitationCode,
        dateOfEnrollment: FieldValue.serverTimestamp(),
      }, { merge: true });

      transaction.update(invitationCodeRef, {
        used: true,
        usedBy: userId,
      });
    });
  }

  async validateUserInvitationCode(userId) {
    const invitationQuerySnapshot = await this.firestore.collection("invitationCodes")
      .where("usedBy", "==", userId)
      .limit(1)
      .get();

    if (invitationQuerySnapshot.empty) {
      throw new https.HttpsError("not-found", `No valid invitation code found for user ${userId}.`);
    }

    const userDoc = await this.firestore.doc(`users/${userId}`).get();

    if (!userDoc.exists || userDoc.data().invitationCode !== invitationQuerySnapshot.docs[0].id) {
      throw new https.HttpsError("failed-precondition", "User document does not exist or contains incorrect invitation code.");
    }
  }
}

module.exports = InvitationCodeVerifier;