import Foundation

extension SelfTest {
    static func clipboardPrivacy() {
        // Excluded apps: exact bundle ID match, nothing excluded without a frontmost app.
        let list = ClipboardExclusions.adding("com.example.bank", to: ["com.example.chat"])
        check("clipboard exclusions: a listed app is excluded", ClipboardExclusions.isExcluded("com.example.bank", in: list))
        check("clipboard exclusions: another app is not", !ClipboardExclusions.isExcluded("com.example.editor", in: list))
        check("clipboard exclusions: no frontmost app is not excluded", !ClipboardExclusions.isExcluded(nil, in: list))
        check("clipboard exclusions: adding twice keeps one entry", ClipboardExclusions.adding("com.example.chat", to: list).count == 2)
        check("clipboard exclusions: removing", ClipboardExclusions.removing("com.example.chat", from: list) == ["com.example.bank"])

        // Secrets: API keys and tokens with known prefixes.
        check("secret: an OpenAI-style key", ClipboardSecrets.isSecret("sk-proj-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
        check("secret: a GitHub token", ClipboardSecrets.isSecret("ghp" + "_abcdefghijklmnopqrstuvwxyz0123456789"))
        check("secret: an AWS access key id", ClipboardSecrets.isSecret("AKIA" + "IOSFODNN7EXAMPLE"))
        check("secret: a Slack token", ClipboardSecrets.isSecret("xoxb" + "-" + "1234567890" + "-" + "abcdefghijklmnopqrstuvwx"))
        check("secret: a key with a low-entropy body is not", !ClipboardSecrets.isSecret("sk-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        check("secret: a URL is not", !ClipboardSecrets.isSecret("https://example.com/sk-related/page"))
        check("secret: prose is not", !ClipboardSecrets.isSecret("call the bank tomorrow at nine"))
        check("secret: a key with a space is not", !ClipboardSecrets.isSecret("sk-proj-abcdefgh ijklmnopqrs"))

        // Payment cards: 13 to 19 digits that pass Luhn.
        check("secret: a valid test card number", ClipboardSecrets.isSecret("4242 4242 4242 4242"))
        check("secret: a valid card number with dashes", ClipboardSecrets.isSecret("4000-0566-5566-5556"))
        check("secret: a 16-digit number that fails Luhn is not", !ClipboardSecrets.isSecret("4242 4242 4242 4241"))
        check("secret: a short number is not", !ClipboardSecrets.isSecret("1234 5678"))
        check("luhn: accepts a valid number", ClipboardSecrets.luhn("79927398713"))
        check("luhn: rejects an invalid number", !ClipboardSecrets.luhn("79927398714"))

        // Expiry: 0 keeps everything, otherwise secrets older than the delay go, pinned items and other items stay.
        let now = Date()
        let old = now.addingTimeInterval(-6 * 60)
        let secretOld = ClipItem(text: "sk-x", date: old, secret: true)
        let secretPinned = ClipItem(date: old, pinned: true, secret: true)
        let plainOld = ClipItem(text: "hello", date: old)
        let secretNew = ClipItem(text: "sk-y", date: now, secret: true)
        let items = [secretOld, secretPinned, plainOld, secretNew]
        check("secret expiry: 0 minutes keeps every secret", ClipboardSecrets.expiredIDs(items, minutes: 0, now: now).isEmpty)
        check("secret expiry: 5 minutes removes only the old unpinned secret", ClipboardSecrets.expiredIDs(items, minutes: 5, now: now) == [secretOld.id])
        check("secret expiry: 30 minutes keeps the old secret", ClipboardSecrets.expiredIDs(items, minutes: 30, now: now).isEmpty)
        check("secret expiry: 1 minute removes the old secret", ClipboardSecrets.expiredIDs(items, minutes: 1, now: now) == [secretOld.id])
    }
}
