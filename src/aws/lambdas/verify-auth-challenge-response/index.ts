// VerifyAuthChallengeResponse
//
// Compares the code the user submitted against the hash CreateAuthChallenge
// stored in privateChallengeParameters, and checks it hasn't expired.
// Returns event.response.answerCorrect. DefineAuthChallenge reads that on
// its next invocation to decide whether to issue tokens, retry, or fail.

import { VerifyAuthChallengeResponseTriggerHandler } from "aws-lambda";
import { createHmac, timingSafeEqual } from "crypto";

function hashOtp(otp: string): string {
  return createHmac("sha256", process.env.OTP_HASH_SECRET as string)
    .update(otp)
    .digest("hex");
}

export const handler: VerifyAuthChallengeResponseTriggerHandler = async (
  event
) => {
  const { hash, expiresAt } = event.request.privateChallengeParameters as {
    hash: string;
    expiresAt: string;
  };
  const submittedAnswer = event.request.challengeAnswer ?? "";

  const notExpired = Date.now() < Number(expiresAt);

  const expected = Buffer.from(hash, "hex");
  const actual = Buffer.from(hashOtp(submittedAnswer), "hex");
  const hashesMatch =
    expected.length === actual.length && timingSafeEqual(expected, actual);

  event.response.answerCorrect = notExpired && hashesMatch;
  return event;
};