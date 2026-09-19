// DefineAuthChallenge
//
// Orchestrator for the CUSTOM_AUTH flow. Cognito calls this trigger after
// InitiateAuth and after every RespondToAuthChallenge, and gives it the full
// history of challenges attempted so far in `event.request.session`.
//
// Responsibilities:
//   - First call (empty session): issue the OTP challenge.
//   - After a correct OTP: issue tokens.
//   - After a wrong OTP, under the attempt limit: issue the challenge again
//     (this causes CreateAuthChallenge to run again and send a fresh code).
//   - After too many wrong attempts: fail closed.

import { DefineAuthChallengeTriggerHandler } from "aws-lambda";

const MAX_ATTEMPTS = 3;

export const handler: DefineAuthChallengeTriggerHandler = async (event) => {
  const session = event.request.session ?? [];

  if (session.length === 0) {
    event.response.challengeName = "CUSTOM_CHALLENGE";
    event.response.issueTokens = false;
    event.response.failAuthentication = false;
    return event;
  }

  const lastAttempt = session[session.length - 1];

  if (
    lastAttempt.challengeName === "CUSTOM_CHALLENGE" &&
    lastAttempt.challengeResult === true
  ) {
    event.response.issueTokens = true;
    event.response.failAuthentication = false;
    return event;
  }

  const attemptsSoFar = session.filter(
    (s) => s.challengeName === "CUSTOM_CHALLENGE"
  ).length;

  if (attemptsSoFar >= MAX_ATTEMPTS) {
    event.response.issueTokens = false;
    event.response.failAuthentication = true;
    return event;
  }

  // Wrong OTP, attempts remain: re-issue the challenge.
  event.response.challengeName = "CUSTOM_CHALLENGE";
  event.response.issueTokens = false;
  event.response.failAuthentication = false;

  console.log(JSON.stringify({
    level: "info",
    event: "login-otp",
    message: "challenge defined"
  }));

  return event;
};