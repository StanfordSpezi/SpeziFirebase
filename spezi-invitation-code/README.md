<!--

This source file is part of the Stanford Spezi open-source project.

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
  
-->

# Spezi Invitation Code

Our Firestore instance also contains a collection called `invitationCodes` with a fixed set of secret, randomly generated codes. During onboarding, we sign the user in anonymously so we can check if they have a valid code. If they do, we assign that code to their new de-anonymized account and remove it from `invitationCodes` so it cannot be used again. This system is designed to hedge against spam and unapproved use.

graph TD
    start["Welcome Screen(s)"]
    in1["Invitation Code View"]
    dec1{Already registered?}
    pro1["Enter code."]
    validation{Valid code?}
    login["Login View"]
    newaccount["New Account View"]
    credentials["Enter credentials."]
    credvalidation{Valid login?}
    home["Home"]

    start --> in1
    in1 --> dec1
    dec1 -->|No| pro1
    dec1 -->|Yes| login
    pro1 --> validation
    validation -->|Yes| newaccount
    newaccount --> home
    login --> credentials
    validation -->|No| in1
    credentials --> credvalidation
    credvalidation -->|No| login
    credvalidation -->|Yes| home

Anytime someone tries to sign up for an account, a blocking cloud function will automatically be triggered, denying sign-up access to users who enter invalid invitation codes.
Since the Firebase instance is set up only to accept authenticated requests, this system eliminates the ability for anyone without an invitation code to send samples to our servers.
