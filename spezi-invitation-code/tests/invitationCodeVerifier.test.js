const admin = require("firebase-admin");
const test = require("firebase-functions-test")();
const InvitationCodeVerifier = require("../index.js");

describe("InvitationCodeVerifier", () => {
  let verifier;

  beforeAll(() => {
    // Initialize the Firebase Admin SDK
    admin.initializeApp();
    verifier = new InvitationCodeVerifier();
  });

  afterAll(() => {
    // Clean up the Firebase Admin SDK
    admin.app().delete();
    test.cleanup();
  });

  test("enrollUserInStudy", async () => {
    // Replace with your test logic
  });
});
