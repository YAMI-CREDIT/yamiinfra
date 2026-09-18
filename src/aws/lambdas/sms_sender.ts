import axios from "axios";

interface SendSmsPayload {
    to: string;
    message: string;
}

interface SmsResponse {
    success: boolean;
    message: string;
    data?: any;
}

export const sendSms = async ({
    to,
    message,
}: SendSmsPayload) => {
    const apiKey = process.env.SMS_SENDER_APIKEY;

    if (!apiKey) {
        throw new Error("SMS_SENDER_APIKEY is missing");
    }

    const phone = to
        .replace(/\s+/g, "")
        .replace(/^\+234/, "234")
        .replace(/^234/, "234")
        .replace(/^0/, "234");

    const { data } = await axios.post(
        process.env.SMS_SENDER_PROVIDER || "https://v3.api.termii.com/api/sms/send",
        {
            api_key: apiKey,
            to: phone,
            from: "FloathHub",
            sms: message,
            type: "plain",
            channel: "generic",
        }
    );

    // Termii returns an error object even with HTTP 200 in some cases
    if (
        data.code !== "ok" &&
        data.message?.toLowerCase() !== "success"
    ) {
        throw new Error(data.message || "SMS sending failed");
    }
    return data;
};
