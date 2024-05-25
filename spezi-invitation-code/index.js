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

/**
 * Invitation code verifier for Spezi Firebase.
 */
class InvitationCodeVerifier {
  /**
   * Create an Invitation Code Verifier.
   * @param {string} [invitationCodePath="invitationCodes"] - The path in Firestore where invitation codes are stored.
   * @param {string} [userPath="users"] - The path in Firestore where user data is stored.
   * @param {RegExp} [invitationCodeRegex=null] - The regex to validate invitation codes. If null, no validation is performed.
   */
  constructor(invitationCodePath = "invitationCodes", userPath = "users", invitationCodeRegex = null) {
    this.firestore = admin.firestore();
    this.invitationCodePath = invitationCodePath;
    this.userPath = userPath;
    this.invitationCodeRegex = invitationCodeRegex;
  }

  /**
   * Enroll a user in a study using an invitation code.
   * @param {string} userId - The ID of the user to enroll.
   * @param {string} invitationCode - The invitation code to use for enrollment.
   * @throws Will throw an error if the userId or invitationCode is invalid, not found or already used, or if the user is already enrolled.
   */
  async enrollUserInStudy(userId, invitationCode) {
    if (!userId) {
      throw new https.HttpsError(
          "invalid-argument",
          "The function must be called with a valid 'userId' input.",
      );
    }

    if (this.invitationCodeRegex && !this.invitationCodeRegex.test(invitationCode)) {
      throw new https.HttpsError(
          "invalid-argument",
          "The function must be called with a 'invitationCode' that matches the configured regex.",
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
      }, {merge: true});

      transaction.update(invitationCodeRef, {
        used: true,
        usedBy: userId,
      });
    });
  }

  /**
   * Validate a user's invitation code.
   * @param {string} userId - The ID of the user whose invitation code is to be validated.
   * @throws Will throw an error if no valid invitation code is found for the user, or if user document does not exist or contains an incorrect code.
   */
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
