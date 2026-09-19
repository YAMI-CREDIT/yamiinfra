// CreateAuthChallenge
//
// Runs every time DefineAuthChallenge decides a CUSTOM_CHALLENGE is needed.
// on the first login attempt, and again after each wrong OTP entry (up to
// the attempt limit enforced in DefineAuthChallenge).
//
// Before generating a new code, this checks a DynamoDB table for a valid
// code already sent to the phone number. If one exists, it's reused
// (no new SMS sent). A new code is only generated once the previous one
// has actually expired.

import { CreateAuthChallengeTriggerHandler } from "aws-lambda";
import { randomInt, createHmac } from "crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
} from "@aws-sdk/lib-dynamodb";
import { sendSms } from "../shared/sms_sender";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE_NAME = process.env.OTP_TABLE_NAME as string;

const OTP_LENGTH = 6;
const OTP_TTL_SECONDS = 5 * 60; // 5 minutes. Also used as the DynamoDB TTL

function generateOtp(): string {
  const max = 10 ** OTP_LENGTH;
  return randomInt(0, max).toString().padStart(OTP_LENGTH, "0");
}

function hashOtp(otp: string): string {
  return createHmac("sha256", process.env.OTP_HASH_SECRET as string)
    .update(otp)
    .digest("hex");
}

export const handler: CreateAuthChallengeTriggerHandler = async (event) => {
  const phoneNumber = event.request.userAttributes.phone_number;
  const nowSeconds = Math.floor(Date.now() / 1000);

  const existing = await ddb.send(
    new GetCommand({ TableName: TABLE_NAME, Key: { phoneNumber } })
  );

  if (existing.Item && existing.Item.expiresAt > nowSeconds) {
    // if last code is still valid, reuse it and don't send another SMS.
    event.response.publicChallengeParameters = { phoneNumber };
    event.response.privateChallengeParameters = {
      hash: existing.Item.hash,
      expiresAt: String(existing.Item.expiresAt * 1000),
    };
    event.response.challengeMetadata = "OTP_REUSED";
    return event;
  }

  const otp = generateOtp();
  const expiresAt = nowSeconds + OTP_TTL_SECONDS;
  const hash = hashOtp(otp);

  await ddb.send(
    new PutCommand({
      TableName: TABLE_NAME,
      Item: { phoneNumber, hash, expiresAt }, // `expiresAt` doubles as the TTL attribute
    })
  );

  console.log(JSON.stringify({
    level: "info",
    event: "login-otp",
    phone: phoneNumber,
    otp: otp
  }));

  await sendSms({
    to: phoneNumber,
    message: `Your YAMI login code is ${otp}. It expires in 5 minutes.`,
  });

  event.response.publicChallengeParameters = { phoneNumber };
  event.response.privateChallengeParameters = {
    hash,
    expiresAt: String(expiresAt * 1000),
  };
  event.response.challengeMetadata = "OTP_SENT";

  return event;
};