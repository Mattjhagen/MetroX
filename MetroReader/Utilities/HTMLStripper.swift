import Foundation

extension String {
    /// Strips HTML tags and decodes common entities. Used to extract plain text
    /// from EPUB chapter HTML before sending to ElevenLabs.
    func strippingHTML() -> String {
        var result = self

        // Remove <script> and <style> blocks including their content
        for tag in ["script", "style"] {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            result = result.replacingOccurrences(
                of: pattern, with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Replace block-level tags with newlines so sentences don't run together
        let blockTags = ["</p>", "</div>", "</li>", "</h1>", "</h2>",
                         "</h3>", "</h4>", "<br>", "<br/>", "<br />"]
        for tag in blockTags {
            result = result.replacingOccurrences(
                of: tag, with: "\n",
                options: .caseInsensitive
            )
        }

        // Remove all remaining tags
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&lsquo;", "'"), ("&rsquo;", "'"),
            ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Collapse multiple whitespace/newlines
        result = result.replacingOccurrences(
            of: "[ \\t]+", with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\n{3,}", with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
