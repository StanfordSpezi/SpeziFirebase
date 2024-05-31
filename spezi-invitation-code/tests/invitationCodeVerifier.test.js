//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

const admin = require("firebase-admin");
const firebaseTest = require("firebase-functions-test")();
const InvitationCodeVerifier = require("../index.js");
const {https} = require("firebase-functions/v2");
const _ = require("lodash");

describe("InvitationCodeVerifier", () => {
  let verifier;
  let firestore;

  beforeAll(() => {
    admin.initializeApp();
    verifier = new InvitationCodeVerifier();
    firestore = admin.firestore();
  });

  afterAll(() => {
    admin.app().delete();
    firebaseTest.cleanup();
  });

  describe("enrollUserInStudy", () => {
    test("should throw an error if userId is invalid", async () => {
      await expect(verifier.enrollUserInStudy("", "validCode")).rejects.toThrow(
          new https.HttpsError(
              "invalid-argument",
              "The function must be called with a valid 'userId' input.",
          ),
      );
    });

    test("should enroll user successfully", async () => {
      await expect(verifier.enrollUserInStudy("HNzc8VN8maeT1uUnABgWozWMPT6x", "gdxRWF6G")).resolves.toBeUndefined();
    });

    test("should throw error if user tries to re-enroll with exact same information", async () => {
      await expect(verifier.enrollUserInStudy("HNzc8VN8maeT1uUnABgWozWMPT6x", "gdxRWF6G")).rejects.toThrow(
          new https.HttpsError(
              "not-found",
              "Invitation code not found or already used.",
          ),
      );
    });
  });

  test("should validate user invitation code successfully", async () => {
    await expect(verifier.validateUserInvitationCode("HNzc8VN8maeT1uUnABgWozWMPT6x")).resolves.toBeUndefined();
  });

  test("should throw an error if user is already enrolled", async () => {
    await expect(verifier.enrollUserInStudy("HNzc8VN8maeT1uUnABgWozWMPT6x", "3Op7vweq")).rejects.toThrow(
        new https.HttpsError(
            "not-found",
            "User is already enrolled in the study.",
        ),
    );
  });

  describe("validateUserInvitationCode", () => {
    test("should throw an error if no valid invitation code found for the user", async () => {
      await expect(verifier.validateUserInvitationCode("user123")).rejects.toThrow(
          new https.HttpsError("not-found", "No valid invitation code found for user user123."),
      );
    });

    test("should throw an error if user document does not exist or contains incorrect invitation code", async () => {
      // Valid invitation code, but user document was never created.
      await expect(verifier.validateUserInvitationCode("uy01WpWa2dP2nJnrpYXjhECT6Sn0")).rejects.toThrow(
          new https.HttpsError("failed-precondition", "User document does not exist or contains incorrect invitation code."),
      );
    });
  });

  test("should throw error if invitation code already used", async () => {
    // User exists, but this particular invitation code has already been redeemed by someone else.
    await expect(verifier.enrollUserInStudy("mDoquC3j6q52FyVNPi11sfSACNMC", "gdxRWF6G")).rejects.toThrow(
        new https.HttpsError(
            "not-found",
            "Invitation code not found or already used.",
        ),
    );
  });

  test("should still accept a valid invitation code from same user (above), without overwriting anything", async () => {
    await expect(verifier.enrollUserInStudy("mDoquC3j6q52FyVNPi11sfSACNMC", "Xkdyv3DF")).resolves.toBeUndefined();
    const userStudyRef = firestore.doc("users/mDoquC3j6q52FyVNPi11sfSACNMC");
    const userStudyDocBefore = await userStudyRef.get();
    await expect(verifier.enrollUserInStudy("mDoquC3j6q52FyVNPi11sfSACNMC", "Xkdyv3DF")).rejects.toThrow(
        new https.HttpsError(
            "not-found",
            "Invitation code not found or already used.",
        ),
    );
    await expect(verifier.validateUserInvitationCode("mDoquC3j6q52FyVNPi11sfSACNMC")).resolves.toBeUndefined();
    const userStudyDocAfter = await userStudyRef.get();
    console.log(userStudyDocBefore.data());
    console.log(userStudyDocAfter.data());
    expect(_.isMatch(userStudyDocAfter.data(), userStudyDocBefore.data())).toBe(true);
  });

  test("should throw an error if invitationCode does not match regex", async () => {
    verifier = new InvitationCodeVerifier(
        "invitationCodes",
        "users",
        /^[A-Z0-9]+$/,
    );
    await expect(verifier.enrollUserInStudy("user123", "invalid_code")).rejects.toThrow(
        new https.HttpsError(
            "invalid-argument",
            "The function must be called with a 'invitationCode' that matches the configured regex.",
        ),
    );
  });
});
