import {
    buildClient,
    CommitmentPolicy,
    KmsKeyringNode,
} from "@aws-crypto/client-node";
import { sendSms } from "../shared/sms_sender";

const { decrypt } = buildClient(CommitmentPolicy.REQUIRE_ENCRYPT_ALLOW_DECRYPT);

const keyring = new KmsKeyringNode({
    generatorKeyId: process.env.KMS_KEY_ARN!,
});

const messageFor = (triggerSource: string, code: string): string => {
    switch (triggerSource) {
        case "CustomSMSSender_SignUp":
        case "CustomSMSSender_ResendCode":
            return `Your Yami verification code is ${code}`;
        case "CustomSMSSender_Authentication":
            return `Your Yami sign-in code is ${code}`;
        case "CustomSMSSender_ForgotPassword":
            return `Your Yami password reset code is ${code}`;
        case "CustomSMSSender_AdminCreateUser":
            return `Your Yami temporary password is ${code}`;
        case "CustomSMSSender_VerifyUserAttribute":
        case "CustomSMSSender_UpdateUserAttribute":
            return `Your Yami attribute verification code is ${code}`;
        default:
            return `Your Yami code is ${code}`;
    }
};

interface CustomSmsSenderEvent {
    triggerSource: string;
    request: {
        code?: string;
        userAttributes: Record<string, string>;
    };
}

export const handler = async (event: CustomSmsSenderEvent) => {
    console.log(
        `CustomSMS sender invoked: triggerSource=${event.triggerSource}, ` +
        `phone=${event.request.userAttributes.phone_number ?? "unknown"}`
    );


    if (!event.request.code) {
        // Some trigger sources (e.g. certain admin flows) may not carry a code.
        // Nothing to send in that case.
        return;
    }

    const ciphertext = Buffer.from(event.request.code, "base64");
    const { plaintext } = await decrypt(keyring, ciphertext);
    const code = plaintext.toString("utf-8");

    const phone = event.request.userAttributes.phone_number;
    if (!phone) {
        throw new Error("No phone_number present on user attributes");
    }

    await sendSms({
        to: phone,
        message: messageFor(event.triggerSource, code),
    });

    console.log(`Called sendSms with phone=${phone} and code=${code}`);

    // Cognito ignores the return value of this trigger; throwing is the
    // only way to signal failure back to the confirmation flow.
};