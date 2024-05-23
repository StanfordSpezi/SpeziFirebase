//
// This source file is part of the StudyApplication based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

const admin = require("firebase-admin");
const {https} = require("firebase-functions/v2");
const {FieldValue} = require("firebase-admin/firestore");

class InvitationCodeVerifier {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async verifyInvitationCode(invitationCode, userId) {
    try {
      const invitationCodeRef = this.firestore.doc(`invitationCodes/${invitationCode}`);
      const invitationCodeDoc = await invitationCodeRef.get();

      if (!invitationCodeDoc.exists || invitationCodeDoc.data().used) {
        throw new https.HttpsError("not-found", "Invitation code not found or already used.");
      }

      const userStudyRef = this.firestore.doc(`users/${userId}`);
      const userStudyDoc = await userStudyRef.get();

      if (userStudyDoc.exists) {
        throw new https.HttpsError("already-exists", "User is already enrolled in the study.");
      }

      await this.firestore.runTransaction(async (transaction) => {
        transaction.set(userStudyRef, {
          invitationCode: invitationCode,
          dateOfEnrollment: FieldValue.serverTimestamp(),
        });

        transaction.update(invitationCodeRef, {
          used: true,
          usedBy: userId,
        });
      });
    } catch (error) {
      throw error;
    }
  }

  async validateUserInvitationCode(userId) {
    try {
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
    } catch (error) {
      throw error;
    }
  }
}

module.exports = InvitationCodeVerifier;