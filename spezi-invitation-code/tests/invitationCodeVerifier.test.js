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

jest.mock("firebase-admin", () => {
  const firestore = {
    doc: jest.fn(),
    collection: jest.fn(),
    runTransaction: jest.fn(),
  };
  return {
    initializeApp: jest.fn(),
    firestore: jest.fn(() => firestore),
    app: jest.fn(() => ({
      delete: jest.fn(),
    })),
  };
});

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
      firestore.doc.mockReturnValueOnce({
        get: jest.fn().mockResolvedValue({exists: true, data: () => ({used: false})}),
      });
      firestore.doc.mockReturnValueOnce({
        get: jest.fn().mockResolvedValue({exists: false}),
      });
      firestore.runTransaction.mockImplementationOnce(async (updateFunction) => {
        await updateFunction({
          set: jest.fn(),
          update: jest.fn(),
        });
      });

      await expect(verifier.enrollUserInStudy("HNzc8VN8maeT1uUnABgWozWMPT6x", "gdxRWF6G")).resolves.toBeUndefined();
    });
  });

  test("should validate user invitation code successfully", async () => {
    firestore.collection.mockReturnValue({
      where: jest.fn().mockReturnThis(),
      limit: jest.fn().mockReturnThis(),
      get: jest.fn().mockResolvedValue({
        empty: false,
        docs: [{id: "validCode"}],
      }),
    });
    firestore.doc.mockReturnValueOnce({
      get: jest.fn().mockResolvedValue({
        exists: true,
        data: () => ({invitationCode: "validCode"}),
      }),
    });

    await expect(verifier.validateUserInvitationCode("HNzc8VN8maeT1uUnABgWozWMPT6x")).resolves.toBeUndefined();
  });

  test("should throw an error if invitationCode does not exist or already used", async () => {
    firestore.doc.mockReturnValueOnce({
      get: jest.fn().mockResolvedValue({exists: false}),
    });

    await expect(verifier.enrollUserInStudy("HNzc8VN8maeT1uUnABgWozWMPT6x", "3Op7vweq")).rejects.toThrow(
        new https.HttpsError(
            "not-found",
            "Invitation code not found or already used.",
        ),
    );
  });

  describe("validateUserInvitationCode", () => {
    test("should throw an error if no valid invitation code found for the user", async () => {
      firestore.collection.mockReturnValue({
        where: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        get: jest.fn().mockResolvedValue({empty: true}),
      });

      await expect(verifier.validateUserInvitationCode("user123")).rejects.toThrow(
          new https.HttpsError("not-found", "No valid invitation code found for user user123."),
      );
    });

    test("should throw an error if user document does not exist or contains incorrect invitation code", async () => {
      firestore.collection.mockReturnValue({
        where: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        get: jest.fn().mockResolvedValue({
          empty: false,
          docs: [{id: "validCode"}],
        }),
      });
      firestore.doc.mockReturnValueOnce({
        get: jest.fn().mockResolvedValue({exists: false}),
      });

      await expect(verifier.validateUserInvitationCode("user123")).rejects.toThrow(
          new https.HttpsError("failed-precondition", "User document does not exist or contains incorrect invitation code."),
      );
    });
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
