import Foundation

struct ReminderParseContext {
    let now: Date
    let calendar: Calendar
    let language: AppLanguage

    init(
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppLanguage = .current
    ) {
        self.now = now
        self.calendar = calendar
        self.language = language
    }
}

struct ReminderParser {
    func makeDraft(
        from input: String,
        source: ReminderSource,
        language: AppLanguage,
        earlyMinutes: Int,
        strikeEnabled: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReminderDraft {
        let context = ReminderParseContext(
            now: now,
            calendar: calendar,
            language: language
        )
        let parsed = ReminderSentenceParser.parse(input, context: context)
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFutureDate = parsed.fireDate.map {
            $0 > now.addingTimeInterval(60)
        } ?? false
        let fireDate = isFutureDate ? parsed.fireDate : nil
        let parseStatus: ReminderParseStatus

        if title.isEmpty {
            parseStatus = .failed
        } else if fireDate == nil {
            parseStatus = .partial
        } else {
            parseStatus = .complete
        }

        return ReminderDraft(
            rawInput: input.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            languageCode: language.rawValue,
            title: title,
            fireDate: fireDate,
            repeatRule: parsed.repeatRule,
            earlyMinutes: earlyMinutes,
            strikeEnabled: strikeEnabled,
            parseStatus: parseStatus
        )
    }
}

struct ReminderSentenceParser {
    struct Result {
        var title: String
        var fireDate: Date?
        var repeatRule: ReminderRepeat
    }

    private static let repeatExpressions: [(ReminderRepeat, [String])] = [
        (.daily, [
            "daily", "every day", "everyday", "each day",
            "毎日", "每日", "每天",
            "매일",
            "tous les jours", "quotidien", "chaque jour",
            "täglich", "jeden tag",
            "her gün", "günlük",
            "todos los días", "diario", "cada día",
            "todos os dias", "diário", "cada dia",
            "каждый день", "ежедневно"
        ]),
        (.weekly, [
            "weekly", "every week", "each week",
            "毎週", "每周",
            "매주",
            "chaque semaine", "hebdomadaire",
            "wöchentlich", "jede woche",
            "her hafta", "haftalık",
            "todas las semanas", "semanal",
            "todas as semanas", "semanal",
            "каждую неделю", "еженедельно"
        ]),
        (.monthly, [
            "monthly", "every month", "each month",
            "毎月", "每月",
            "매달", "매월",
            "chaque mois", "mensuel",
            "monatlich", "jeden monat",
            "her ay", "aylık",
            "todos los meses", "mensual",
            "todos os meses", "mensal",
            "каждый месяц", "ежемесячно"
        ])
    ]

    static func parse(
        _ input: String,
        context: ReminderParseContext = ReminderParseContext()
    ) -> Result {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsText = text as NSString
        var removalRanges: [NSRange] = []
        var repeatRule: ReminderRepeat = .once

        if let repeatMatch = firstRepeatMatch(in: text) {
            repeatRule = repeatMatch.rule
            removalRanges.append(repeatMatch.range)
        }

        let dateResult = detectDate(in: text, context: context)
        if dateResult.date != nil, let range = dateResult.range {
            removalRanges.append(dateRangeIncludingPreposition(in: nsText, dateRange: range))
        }

        let mutable = NSMutableString(string: text)
        for range in mergedRanges(removalRanges).sorted(by: { $0.location > $1.location }) {
            guard range.location != NSNotFound,
                  NSMaxRange(range) <= mutable.length else {
                continue
            }
            mutable.replaceCharacters(in: range, with: " ")
        }

        var title = (mutable as String)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty, dateResult.date == nil {
            title = text
        }

        return Result(
            title: title,
            fireDate: dateResult.date,
            repeatRule: repeatRule
        )
    }

    private static func firstRepeatMatch(
        in text: String
    ) -> (rule: ReminderRepeat, range: NSRange)? {
        let nsText = text as NSString
        let matches = repeatExpressions.flatMap { rule, expressions in
            expressions.compactMap { expression -> (ReminderRepeat, NSRange)? in
                let range = nsText.range(
                    of: expression,
                    options: .caseInsensitive
                )
                guard range.location != NSNotFound else { return nil }
                return (rule, range)
            }
        }

        return matches
            .sorted {
                if $0.1.location == $1.1.location {
                    return $0.1.length > $1.1.length
                }
                return $0.1.location < $1.1.location
            }
            .first
            .map { match in
                (rule: match.0, range: match.1)
            }
    }

    private static func dateRangeIncludingPreposition(
        in text: NSString,
        dateRange: NSRange
    ) -> NSRange {
        let prefixRange = NSRange(location: 0, length: dateRange.location)
        let prefix = text.substring(with: prefixRange) as NSString
        let prepositionRange = prefix.range(
            of: #"\b(?:on|at|by)\s+$"#,
            options: [.regularExpression, .caseInsensitive]
        )

        guard prepositionRange.location != NSNotFound else {
            return dateRange
        }

        return NSRange(
            location: prepositionRange.location,
            length: NSMaxRange(dateRange) - prepositionRange.location
        )
    }

    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { $0.location < $1.location }

        var result: [NSRange] = []
        for range in sorted {
            guard let previous = result.last else {
                result.append(range)
                continue
            }

            if NSMaxRange(previous) >= range.location {
                let end = max(NSMaxRange(previous), NSMaxRange(range))
                result[result.count - 1] = NSRange(
                    location: previous.location,
                    length: end - previous.location
                )
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func detectDate(
        in text: String,
        context: ReminderParseContext
    ) -> (date: Date?, range: NSRange?) {
        let types: NSTextCheckingResult.CheckingType = [.date]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return (nil, nil)
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: range)
        guard let match = matches.first else {
            return (nil, nil)
        }
        return (match.date, match.range)
    }
}
