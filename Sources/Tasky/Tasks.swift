import AppKit
import EventKit

// F24 할 일·일정

/// 한 줄 자연어 → 제목·날짜. 자체 한국어 규칙을 먼저 쓰고, 맞는 게 없으면 NSDataDetector.
enum QuickParse {
    struct Result: Equatable { var title: String; var date: Date?; var hasTime: Bool }

    /// "내일배움카드"처럼 한글 낱말 안에 붙은 매치인지
    private static func insideWord(_ text: String, _ r: Range<String.Index>) -> Bool {
        func hangul(_ c: Swift.Character?) -> Bool { c.map { ("가" as Swift.Character)..."힣" ~= $0 } ?? false }
        let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
        let after = r.upperBound < text.endIndex ? text[r.upperBound] : nil
        return hangul(before) || hangul(after)
    }

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        var s = text
        var day: Date?
        var hour: Int?, minute = 0
        let today = calendar.startOfDay(for: now)
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]   // Calendar weekday 1...7

        /// 첫 매치를 찾아 지우고 묶음 문자열을 돌려준다.
        func take(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            let groups = (0..<m.numberOfRanges).map { i -> String in
                guard let r = Range(m.range(at: i), in: s) else { return "" }
                return String(s[r])
            }
            s.replaceSubrange(Range(m.range, in: s)!, with: " ")
            return groups
        }
        func add(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today)! }
        func monthDay(_ m: Int, _ d: Int) -> Date? {
            var c = calendar.dateComponents([.year], from: today); c.month = m; c.day = d
            guard let date = calendar.date(from: c), calendar.component(.day, from: date) == d else { return nil }
            return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
        }

        var invalid = false   // 없는 날을 쓴 경우 NSDataDetector가 엉뚱한 날로 읽지 않게
        // 날
        if let g = take("다음\\s*주\\s*([일월화수목금토])요일") {
            let w = weekdays.firstIndex(of: g[1])! + 1
            let cur = calendar.component(.weekday, from: today)
            let toMonday = (9 - cur) % 7 == 0 ? 7 : (9 - cur) % 7          // 다음 주 월요일까지
            day = add(toMonday + (w + 5) % 7)                                // 월=0 … 일=6
        } else if let before = Optional(s), let g = take("(\\d{1,2})월\\s*(\\d{1,2})일") {
            day = monthDay(Int(g[1])!, Int(g[2])!)
            if day == nil { s = before; invalid = true }                     // 없는 날(2/30 등)은 제목에 남긴다
        } else if let before = Optional(s), let g = take("(?<![\\d:])(\\d{1,2})/(\\d{1,2})(?![\\d])") {
            day = monthDay(Int(g[1])!, Int(g[2])!)
            if day == nil { s = before; invalid = true }
        } else if let g = take("(\\d{1,3})\\s*일\\s*(뒤|후)") {
            day = add(Int(g[1])!)
        } else if let g = take("(?<![가-힣])(오늘|내일|모레|글피)(?=까지|부터|에|은|는|도|[^가-힣]|$)") {
            day = add(["오늘": 0, "내일": 1, "모레": 2, "글피": 3][g[1]]!)
        } else if let g = take("([일월화수목금토])요일") {
            let w = weekdays.firstIndex(of: g[1])! + 1
            day = add((w - calendar.component(.weekday, from: today) + 7) % 7)
        }

        // 때
        var nextDay = false
        if let g = take("(오전|오후|아침|저녁|밤|새벽)?\\s*(?<!\\d)(\\d{1,2})시(?!간)(\\s*(\\d{1,2})분|\\s*반(?![가-힣]))?") {
            var h = Int(g[2])!
            switch g[1] {
            case "저녁" where h == 12, "밤" where h == 12: h = 0; nextDay = true
            case "오후", "저녁", "밤": if h < 12 { h += 12 }
            case "오전", "아침", "새벽": if h == 12 { h = 0 }
            default: if (1...6).contains(h) { h += 12 }                    // 사용자 결정 2026-11-03
            }
            if g[3].contains("반") { minute = 30 } else if let m = Int(g[4]) { minute = m }
            if h < 24 && minute < 60 { hour = h }
        } else if let g = take("(?<!\\d)(\\d{1,2}):(\\d{2})(?!\\d)") {
            let h = Int(g[1])!, m = Int(g[2])!
            if h < 24 && m < 60 { hour = h; minute = m }
        }

        let title = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if day != nil || hour != nil {
            var date = day ?? today
            if let hour {
                date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
                if nextDay || (day == nil && date < now) { date = calendar.date(byAdding: .day, value: 1, to: date)! }
            }
            return Result(title: title, date: date, hasTime: hour != nil)
        }

        // 대체: NSDataDetector (영어 등)
        if !invalid, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = det.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let date = m.date, let r = Range(m.range, in: text), !insideWord(text, r) {
            let found = text[r].lowercased()
            let hasTime = found.range(of: "\\d:\\d|\\d\\s*(am|pm|a\\.m|p\\.m)|\\bat\\s+\\d|o'clock|noon|midnight|tonight", options: .regularExpression) != nil
            var rest = text; rest.replaceSubrange(r, with: " ")
            let t = rest.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return Result(title: t, date: hasTime ? date : calendar.startOfDay(for: date), hasTime: hasTime)
        }
        return Result(title: title, date: nil, hasTime: false)
    }
}

// MARK: - 항목과 순수 계산 (자체 검사 대상)

struct TaskItem {
    var id: String
    var title: String
    var date: Date?
    var hasTime: Bool
    var isEvent: Bool
    var ref: EKCalendarItem?
    /// 끝낸 할 일(빠른 실행 검색에서만 씀)
    var done = false
}

enum TaskLogic {
    /// 오늘(지난 것 포함) / 다가오는 일 / 날짜 없음. 각 묶음은 시간 순.
    /// 오늘 진행: 끝낸 수 / (끝낸 수 + 오늘 남은 할 일)
    static func progress(done: Int, left: Int) -> (fraction: Double, text: String) {
        let total = done + left
        return (total == 0 ? 0 : Double(done) / Double(total), "오늘 \(done)/\(total)")
    }

    static func groups(_ items: [TaskItem], now: Date, calendar: Calendar = .current) -> (today: [TaskItem], upcoming: [TaskItem], undated: [TaskItem]) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let dated = items.filter { $0.date != nil }.sorted { $0.date! < $1.date! }
        return (dated.filter { $0.date! < tomorrow }, dated.filter { $0.date! >= tomorrow }, items.filter { $0.date == nil })
    }

    /// 2분 전부터 1분 뒤 사이에 시각이 오는 항목(잠자기·타이머 지연으로 놓치지 않게)(시간 있는 것만, 이미 알린 것 제외). `snoozed`: 10분 뒤로 미룬 시각.
    static func due(_ items: [TaskItem], now: Date, alerted: Set<String>, snoozed: [String: Date] = [:]) -> [TaskItem] {
        items.filter { item in
            guard item.hasTime, let t = snoozed[item.id] ?? item.date, let key = alertKey(item, at: t) else { return false }
            return t >= now.addingTimeInterval(-120) && t < now.addingTimeInterval(60) && !alerted.contains(key)
        }
    }

    /// 남은 할 일: 오늘(지난 것 포함)·날짜 없는 할 일(일정 제외), 오늘 것 먼저
    static func pending(_ items: [TaskItem], now: Date, calendar: Calendar = .current) -> [TaskItem] {
        let g = groups(items.filter { !$0.isEvent }, now: now, calendar: calendar)
        return g.today + g.undated
    }

    /// F27 오늘 카드 일정: 지금(시작 5분 지난 것까지)부터 `days`일 뒤 자정 전까지, 시간 순
    static func upcomingEvents(_ items: [TaskItem], now: Date, days: Int, calendar: Calendar = .current) -> [TaskItem] {
        let end = calendar.date(byAdding: .day, value: max(1, days), to: calendar.startOfDay(for: now))!
        return items.filter { i in
            guard i.isEvent, let d = i.date else { return false }
            return d < end && (i.hasTime ? d >= now.addingTimeInterval(-300) : d >= calendar.startOfDay(for: now))
        }.sorted { $0.date! < $1.date! }
    }

    /// F27 일정 알림 단계(분 전)
    /// F28: 30분 전은 뺐다 — 사용자가 1시간 전 알림에서 '다시 알려 줘요'로 직접 정한다(사용자 결정 2026-11-06)
    static let eventStages = [60, 0]

    /// F27: 지금 띄울 일정 알림. 시작 1시간 전부터 시작 2분 뒤까지, 지난 단계 중 가장 최근 것 하나만.
    /// `keys`는 이번에 지난 모든 단계(늦게 켜져도 앞 단계를 다시 띄우지 않게).
    static func eventAlerts(_ items: [TaskItem], now: Date, sent: Set<String>) -> [(item: TaskItem, minutes: Int, keys: [String])] {
        items.compactMap { item in
            guard item.isEvent, item.hasTime, let d = item.date,
                  now >= d.addingTimeInterval(-Double(eventStages[0]) * 60), now < d.addingTimeInterval(120) else { return nil }
            let fired = eventStages.filter { d.addingTimeInterval(-Double($0) * 60) <= now }
            guard let latest = fired.min() else { return nil }
            let key = { (m: Int) in "\(item.id)@\(Int(d.timeIntervalSince1970))#\(m)" }
            guard !sent.contains(key(latest)) else { return nil }
            return (item, latest, fired.map(key))
        }
    }

    /// F27: N분마다 남은 할 일 알림(0 = 끄기, 남은 게 없으면 안 띄움)
    static func nudgeDue(remaining: Int, last: Date, now: Date, minutes: Int) -> Bool {
        minutes > 0 && remaining > 0 && now.timeIntervalSince(last) >= Double(minutes) * 60
    }

    /// 알림 패널 윗줄: "1시간 뒤 일정" · "30분 뒤 일정" · "지금 시작해요"
    static func eventLead(start: Date, now: Date) -> String {
        let m = Int((start.timeIntervalSince(now) / 60).rounded())
        if m <= 0 { return "지금 시작해요" }
        return m >= 60 ? "\(m / 60)시간\(m % 60 == 0 ? "" : " \(m % 60)분") 뒤 일정" : "\(m)분 뒤 일정"
    }

    static func alertKey(_ item: TaskItem, at date: Date?) -> String? {
        date.map { "\(item.id)@\(Int($0.timeIntervalSince1970))" }
    }
}

// MARK: - EventKit 저장소

final class TaskStore {
    static let shared = TaskStore()
    let store = EKEventStore()
    private(set) var items: [TaskItem] = []
    /// 오늘 끝낸 미리 알림 수(할 일 창 진행 막대)
    private(set) var doneToday = 0
    var onChange: () -> Void = {}
    private var observing = false

    static var remindersOn: Bool {
        get { UserDefaults.standard.bool(forKey: "tasksReminders") }
        set { UserDefaults.standard.set(newValue, forKey: "tasksReminders") }
    }
    static var eventsOn: Bool {
        get { UserDefaults.standard.bool(forKey: "tasksEvents") }
        set { UserDefaults.standard.set(newValue, forKey: "tasksEvents") }
    }
    static var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "tasksSound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tasksSound") }
    }
    static var anyOn: Bool { remindersOn || eventsOn }
    /// F27: 일정을 며칠 뒤까지 볼지(1~7, 기본 7)
    static var eventDays: Int {
        get { min(7, max(1, UserDefaults.standard.object(forKey: "eventDays") as? Int ?? 7)) }
        set { UserDefaults.standard.set(min(7, max(1, newValue)), forKey: "eventDays"); shared.onChange() }
    }
    /// F27: 남은 할 일을 몇 분마다 알릴지(0 = 끄기, 기본 60)
    static var nudgeMinutes: Int {
        get { UserDefaults.standard.object(forKey: "nudgeMinutes") as? Int ?? 60 }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "nudgeMinutes") }
    }

    /// 번들로 실행했고 권한 설명 키가 있어야 요청할 수 있다(없으면 요청 시 앱이 죽을 수 있음).
    static func canAsk(_ type: EKEntityType) -> Bool {
        let key = type == .reminder ? "NSRemindersFullAccessUsageDescription" : "NSCalendarsFullAccessUsageDescription"
        return Bundle.main.bundleIdentifier != nil && Bundle.main.object(forInfoDictionaryKey: key) != nil
    }
    static func granted(_ type: EKEntityType) -> Bool { EKEventStore.authorizationStatus(for: type) == .fullAccess }
    static func openPermission(_ type: EKEntityType) {
        let pane = type == .reminder ? "Privacy_Reminders" : "Privacy_Calendars"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// 설정에서 켤 때만 부른다.
    func setEnabled(_ type: EKEntityType, _ on: Bool, done: @escaping () -> Void) {
        if type == .reminder { Self.remindersOn = on } else { Self.eventsOn = on }
        guard on, Self.canAsk(type), !Self.granted(type) else { start(); done(); return }
        let finish: (Bool, Error?) -> Void = { [weak self] _, _ in DispatchQueue.main.async { self?.start(); done() } }
        if type == .reminder { store.requestFullAccessToReminders(completion: finish) }
        else { store.requestFullAccessToEvents(completion: finish) }
    }

    /// 켜져 있고 권한이 있으면 읽고 바깥 변경을 감시한다. 앱 시작 때도 부른다(권한 창은 띄우지 않음).
    private var asking: Set<EKEntityType> = []

    func start() {
        // 켜 둔 채인데 권한이 아직 정해지지 않았으면(권한 초기화·앱 서명 변경 뒤) 다시 묻는다
        for (type, on) in [(EKEntityType.reminder, Self.remindersOn), (.event, Self.eventsOn)]
            where on && Self.canAsk(type) && EKEventStore.authorizationStatus(for: type) == .notDetermined && !asking.contains(type) {
            asking.insert(type)
            setEnabled(type, true) { [weak self] in self?.asking.remove(type); self?.reload() }
        }
        if !observing, Self.anyOn {
            observing = true
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.reload() }
        }
        TaskAlerts.shared.apply()
        reload()
    }

    private var useReminders: Bool { Self.remindersOn && Self.granted(.reminder) }
    private var useEvents: Bool { Self.eventsOn && Self.granted(.event) }
    var canAddEvent: Bool { useEvents }
    var canAddReminder: Bool { useReminders }

    func reminderCalendar() -> EKCalendar? {
        UserDefaults.standard.string(forKey: "tasksReminderList").flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewReminders()
    }
    func eventCalendar() -> EKCalendar? {
        UserDefaults.standard.string(forKey: "tasksEventCalendar").flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
    }

    func reload() {
        var events: [TaskItem] = []
        if useEvents {
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 8, to: start)!
            events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
                .map { TaskItem(id: "\($0.eventIdentifier ?? "")@\(Int($0.startDate.timeIntervalSince1970))", title: $0.title ?? "",
                                date: $0.startDate, hasTime: !$0.isAllDay, isEvent: true, ref: $0) }
        }
        guard useReminders else { items = events; changed(); return }
        store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { [weak self] rs in
            let list = (rs ?? []).map { r -> TaskItem in
                let c = r.dueDateComponents
                return TaskItem(id: r.calendarItemIdentifier, title: r.title ?? "", date: c.flatMap { Calendar.current.date(from: $0) },
                                hasTime: c?.hour != nil, isEvent: false, ref: r)
            }
            guard let self else { return }
            let start = Calendar.current.startOfDay(for: Date())
            self.store.fetchReminders(matching: self.store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: Date(), calendars: nil)) { done in
                DispatchQueue.main.async { self.items = events + list; self.doneToday = done?.count ?? 0; self.changed() }
            }
        }
    }

    /// 빠른 실행 검색용: 앞뒤 1년 일정 + 모든 미리 알림(끝낸 것 포함). 반복 일정은 지금과 가장 가까운 한 번만.
    /// 캘린더 앞뒤 1년 + 미리 알림 전부(끝낸 것 포함). 캘린더는 반복 일정이 많으면 느려서 뒤에서 읽고, 결과는 메인에서 돌려준다.
    func searchIndex(_ done: @escaping ([TaskItem]) -> Void) {
        let useEvents = useEvents, useReminders = useReminders, store = store
        DispatchQueue.global(qos: .userInitiated).async {
            var events: [TaskItem] = []
            if useEvents {
                let now = Date(), year: TimeInterval = 365 * 86400
                var nearest: [String: TaskItem] = [:]
                for e in store.events(matching: store.predicateForEvents(withStart: now - year, end: now + year, calendars: nil)) {
                    let key = e.calendarItemIdentifier
                    let item = TaskItem(id: "\(e.eventIdentifier ?? "")@\(Int(e.startDate.timeIntervalSince1970))", title: e.title ?? "",
                                        date: e.startDate, hasTime: !e.isAllDay, isEvent: true, ref: e)
                    if let old = nearest[key], let od = old.date, abs(od.timeIntervalSince(now)) <= abs(e.startDate.timeIntervalSince(now)) { continue }
                    nearest[key] = item
                }
                events = Array(nearest.values)
            }
            guard useReminders else { DispatchQueue.main.async { done(events) }; return }
            store.fetchReminders(matching: store.predicateForReminders(in: nil)) { rs in
                let list = (rs ?? []).map { r -> TaskItem in
                    let c = r.dueDateComponents
                    return TaskItem(id: r.calendarItemIdentifier, title: r.title ?? "", date: c.flatMap { Calendar.current.date(from: $0) },
                                    hasTime: c?.hour != nil, isEvent: false, ref: r, done: r.isCompleted)
                }
                DispatchQueue.main.async { done(events + list) }
            }
        }
    }

    /// 시간이 있고 `asEvent`면 일정(1시간), 아니면 할 일. 시각이 있으면 그 시각 알람을 붙인다.
    /// 저장하지 못하면 사용자에게 보여 줄 이유를 돌려준다.
    func add(title: String, date: Date?, hasTime: Bool, asEvent: Bool) -> String? {
        let name = title.isEmpty ? "새 할 일" : title
        do {
            if asEvent, hasTime, let date, useEvents, let cal = eventCalendar() {
                let e = EKEvent(eventStore: store)
                e.title = name; e.startDate = date; e.endDate = date.addingTimeInterval(3600); e.calendar = cal
                e.addAlarm(EKAlarm(relativeOffset: 0))
                try store.save(e, span: .thisEvent)
            } else if useReminders, let cal = reminderCalendar() {
                let r = EKReminder(eventStore: store)
                r.title = name; r.calendar = cal
                if let date {
                    r.dueDateComponents = Calendar.current.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: date)
                    if hasTime { r.addAlarm(EKAlarm(absoluteDate: date)) }
                }
                try store.save(r, commit: true)
            } else if useEvents {
                return "일정에는 시간이 필요해요. 시간 없는 일은 설정에서 '할 일'을 켜면 저장할 수 있어요."
            } else { return "설정 '할 일·일정'에서 켜고 권한을 주세요." }
        } catch { NSLog("Tasky 할 일 저장 실패: \(error)"); return "저장하지 못했어요: \(error.localizedDescription)" }
        reload()
        return nil
    }

    static let changedNote = Notification.Name("TaskyTasksChanged")
    /// 창(`onChange`)과 펫 배지(알림)에 함께 알린다
    private func changed() {
        onChange()
        NotificationCenter.default.post(name: Self.changedNote, object: nil)
    }

    /// 이름·날짜 고치기. 미리 알림은 마감과 알람을, 일정은 길이를 유지한 채 시작 시각을 바꾼다.
    func update(_ item: TaskItem, title: String, date: Date?, hasTime: Bool) -> String? {
        guard let ref = item.ref, ref.calendar.allowsContentModifications else { return "이 항목은 고칠 수 없어요." }
        ref.title = title.isEmpty ? ref.title : title
        do {
            if let r = ref as? EKReminder {
                r.dueDateComponents = date.map { Calendar.current.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: $0) }
                r.alarms = hasTime ? date.map { [EKAlarm(absoluteDate: $0)] } : nil
                try store.save(r, commit: true)
            } else if let e = ref as? EKEvent {
                guard let date else { return "일정에는 날짜가 필요해요." }
                let length = max(e.endDate.timeIntervalSince(e.startDate), 3600)
                e.isAllDay = !hasTime
                e.startDate = hasTime ? date : Calendar.current.startOfDay(for: date)
                e.endDate = hasTime ? date.addingTimeInterval(length) : e.startDate.addingTimeInterval(86400)
                try store.save(e, span: .thisEvent)
            }
        } catch { NSLog("Tasky 고치기 실패: \(error)"); store.reset(); reload(); return "고치지 못했어요: \(error.localizedDescription)" }
        reload()
        return nil
    }

    func complete(_ item: TaskItem) {
        guard let r = item.ref as? EKReminder else { return }
        r.isCompleted = true
        try? store.save(r, commit: true)
        reload()
        DoneToast.show(item.title) { [weak self] in   // F26: 4초 동안 되돌리기
            r.isCompleted = false
            try? self?.store.save(r, commit: true)
            self?.reload()
        }
    }

    func delete(_ item: TaskItem) {
        guard item.ref?.calendar.allowsContentModifications == true else { return }
        if let r = item.ref as? EKReminder { try? store.remove(r, commit: true) }
        else if let e = item.ref as? EKEvent { try? store.remove(e, span: .thisEvent) }
        reload()
    }

    /// 10분 뒤: 미리 알림은 알람을 그 시각 하나로 바꿔 macOS 알림도 다시 오게 한다(쌓이지 않게 교체).
    /// 일정은 사용자·공유 캘린더 항목이라 바꾸지 않고 펫 반응만 미룬다.
    func snooze(_ item: TaskItem, until date: Date) {
        guard let r = item.ref as? EKReminder, r.calendar.allowsContentModifications else { return }
        r.alarms = [EKAlarm(absoluteDate: date)]
        do { try store.save(r, commit: true) } catch { NSLog("Tasky 10분 뒤 저장 실패: \(error)") }
    }
}

// MARK: - 펫 반응 (macOS 알림은 미리 알림·캘린더 앱이 보낸다, 사용자 결정 2026-11-03)

/// F27 알림 패널에 띄울 것
enum TaskNotice {
    case event(TaskItem, minutes: Int)   // 60·30·0분 전
    case todo(TaskItem)                  // 시각을 정한 할 일
    case nudge([TaskItem])               // N분마다 남은 할 일
    var eventID: String? { if case .event(let i, _) = self { return i.id }; return nil }
}

final class TaskAlerts {
    static let shared = TaskAlerts()
    /// 보이는 첫 펫이 받는다(App이 연결).
    var onDue: (TaskNotice) -> Void = { _ in }
    private var timer: Timer?
    /// 이미 띄운 알림·끈 일정. 앱을 다시 켜도 같은 알림을 또 띄우지 않게 저장한다(F28: 다시 켤 때마다 다시 왔다)
    private var alerted: Set<String> = TaskAlerts.load("taskAlerted") { didSet { TaskAlerts.save(alerted, "taskAlerted") } }
    private var snoozed: [String: Date] = [:]
    private var lastNudge = Date()
    /// 일정 '다시 알려 줘요': 다시 띄울 시각
    private var again: [(at: Date, item: TaskItem)] = []
    /// '알겠어요(알림 끄기)'를 누른 일정(id@시작) — 시작 알림도 오지 않는다
    private var muted: Set<String> = TaskAlerts.load("taskMuted") { didSet { TaskAlerts.save(muted, "taskMuted") } }

    /// 키 끝의 시각(…@초 또는 …@초#단계)이 이틀 넘게 지난 것은 버린다
    static func pruned(_ keys: Set<String>, now: Date) -> Set<String> {
        keys.filter { k in
            let tail = k.split(separator: "@").last.map { $0.split(separator: "#").first.map(String.init) ?? "" } ?? ""
            guard let t = Double(tail) else { return true }
            return t > now.timeIntervalSince1970 - 2 * 86400
        }
    }
    private static func load(_ key: String) -> Set<String> { pruned(Set(UserDefaults.standard.stringArray(forKey: key) ?? []), now: Date()) }
    private static func save(_ set: Set<String>, _ key: String) { UserDefaults.standard.set(Array(set), forKey: key) }
    static func muteKey(_ i: TaskItem) -> String { "\(i.id)@\(Int(i.date?.timeIntervalSince1970 ?? 0))" }

    func apply() {
        timer?.invalidate(); timer = nil
        guard TaskStore.anyOn else { return }
        lastNudge = Date()
        timer = Ticker.every("할 일 알림", 30) { [weak self] _ in self?.check() }
        check()
    }

    private var lastReload = Date()

    private func check() {
        let now = Date()
        if now.timeIntervalSince(lastReload) > 900 || !Calendar.current.isDate(now, inSameDayAs: lastReload) {
            lastReload = now
            TaskStore.shared.reload()   // 결과는 비동기로 오므로 다음 확인부터 반영
        }
        let items = TaskStore.shared.items
        for a in TaskLogic.eventAlerts(items, now: now, sent: alerted) {
            alerted.formUnion(a.keys)
            if !muted.contains(Self.muteKey(a.item)) { post(.event(a.item, minutes: a.minutes)) }
        }
        for (i, a) in again.enumerated().reversed() where a.at <= now {
            again.remove(at: i)
            if !muted.contains(Self.muteKey(a.item)) { post(.event(a.item, minutes: max(0, Int((a.item.date ?? now).timeIntervalSince(now) / 60)))) }
        }
        for item in TaskLogic.due(items.filter { !$0.isEvent }, now: now, alerted: alerted, snoozed: snoozed) {
            if let key = TaskLogic.alertKey(item, at: snoozed[item.id] ?? item.date) { alerted.insert(key) }
            post(.todo(item))
        }
        let pending = TaskLogic.pending(items, now: now)
        if TaskLogic.nudgeDue(remaining: pending.count, last: lastNudge, now: now, minutes: TaskStore.nudgeMinutes) {
            lastNudge = now
            post(.nudge(pending))
        }
    }

    /// 집중 모드면 띄우지 않는다(F27)
    private func post(_ n: TaskNotice) {
        guard !FocusState.isOn else { return }
        onDue(n)
    }

    /// 알겠어요(알림 끄기): 이 일정의 남은 알림(시작할 때 포함)을 보내지 않는다
    func mute(_ item: TaskItem) { muted.insert(Self.muteKey(item)); again.removeAll { $0.item.id == item.id } }

    func snooze(_ item: TaskItem, minutes: Int = 10) {
        let t = Date().addingTimeInterval(Double(minutes) * 60)
        if item.isEvent { again.append((t, item)); return }
        snoozed[item.id] = t
        TaskStore.shared.snooze(item, until: t)
    }

    /// '나중에': 다음 알림까지 처음부터 다시 센다
    func nudgeLater() { lastNudge = Date() }
}

/// F27 알림 패널 C '지금 하나에 집중': 펫 옆, 포커스를 뺏지 않음. 한 번에 하나, 나머지는 줄을 선다.
final class TaskAlertPanel {
    private static var current: TaskAlertPanel?
    private static var queue: [(TaskNotice, CGRect, CGRect)] = []
    private let panel: FloatingPanel
    private let notice: TaskNotice

    static func show(_ n: TaskNotice, nextTo petFrame: CGRect, in v: CGRect) {
        if let c = current {
            // 같은 일정의 다음 단계면 바꿔 끼운다(쌓지 않음)
            if let id = n.eventID, c.notice.eventID == id { c.close(next: false) } else {
                queue.removeAll { q in n.eventID != nil && q.0.eventID == n.eventID }
                queue.append((n, petFrame, v)); return
            }
        }
        current = TaskAlertPanel(n, petFrame, v)
    }

    /// 윗줄·제목·아랫줄·주 버튼
    static func texts(_ n: TaskNotice, now: Date) -> (lead: String, title: String, sub: String, main: String) {
        switch n {
        case .event(let i, _):
            let start = (i.date ?? now).timeIntervalSince(now) < 60
            return (TaskLogic.eventLead(start: i.date ?? now, now: now), i.title, i.date.map { TaskWindow.timeText($0, hasTime: true) } ?? "", start ? "알겠어요" : "알겠어요 (알림 끄기)")
        case .todo(let i):
            return ("지금 할 일", i.title, i.date.map { TaskWindow.timeText($0, hasTime: true) } ?? "", "끝냈어요")
        case .nudge(let list):
            return ("남은 할 일 \(list.count)개", list.first?.title ?? "", list.first.flatMap { $0.date.map { TaskWindow.timeText($0, hasTime: $0 != Calendar.current.startOfDay(for: $0)) } } ?? "날짜 없음", "끝냈어요")
        }
    }

    /// '다시 알려 줘요' 칩(분)과 굴리는 고르기 값
    static let chips = [5, 10, 30, 60]
    static let wheelValues = [1, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
    static func minutesText(_ m: Int) -> String { m >= 60 ? (m % 60 == 0 ? "\(m / 60)시간" : "\(m / 60)시간 \(m % 60)분") : "\(m)분" }

    private init(_ n: TaskNotice, _ petFrame: CGRect, _ v: CGRect, expanded: Bool = false) {
        notice = n
        let t = Self.texts(n, now: Date())
        let next: [TaskItem] = { if case .nudge(let l) = n { return Array(l.dropFirst().prefix(2)) }; return [] }()
        let isEvent = n.eventID != nil
        // 시작 시각에 온 일정 알림은 미룰 필요가 없다(버튼 하나)
        let atStart: Bool = { if case .event(let i, _) = n, let d = i.date { return d.timeIntervalSinceNow < 60 }; return false }()
        let w: CGFloat = 320
        let base: CGFloat = atStart ? 140 : 214 + (isEvent ? 18 : 0)
        let h: CGFloat = base + (expanded ? 190 : 0) + (next.isEmpty ? 0 : 30 + CGFloat(next.count) * 20)
        let size = CGSize(width: w, height: h)
        let shown = petFrame.intersection(v).isNull ? petFrame : petFrame.intersection(v)
        var x = shown.midX > v.midX ? shown.minX - w - 8 : shown.maxX + 8
        x = min(max(x, v.minX + 8), v.maxX - w - 8)
        let y = min(max(shown.midY - h / 2, v.minY + 8), v.maxY - h - 8)
        panel = FloatingPanel(size: size)
        panel.setFrame(CGRect(x: x, y: y, width: w, height: h), display: false)
        panel.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: CGRect(origin: .zero, size: size))
        let glass = makeGlass(cornerRadius: 20, frame: root.bounds)
        glass.autoresizingMask = [.width, .height]
        root.addSubview(glass)

        func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
            let f = NSTextField(labelWithString: s)
            f.font = .systemFont(ofSize: size, weight: weight); f.textColor = color
            f.lineBreakMode = .byTruncatingTail; f.maximumNumberOfLines = 1
            return f
        }
        let item: TaskItem? = { switch n { case .event(let i, _), .todo(let i): return i; case .nudge: return nil } }()
        let snooze: (Int) -> Void = { [weak self] m in
            if let item { TaskAlerts.shared.snooze(item, minutes: m) } else { TaskAlerts.shared.nudgeLater() }
            self?.close(next: true)
        }
        let main = PillButton(t.main, primary: true) { [weak self] in
            guard let self else { return }
            switch n {
            case .todo(let i): TaskStore.shared.complete(i)
            case .nudge(let l): if let f = l.first { TaskStore.shared.complete(f) }
            case .event(let i, _): TaskAlerts.shared.mute(i)
            }
            self.close(next: true)
        }
        var views: [NSView] = [label(t.lead, 12, .semibold, .white.withAlphaComponent(0.6)), label(t.title, 22, .heavy, .white), label(t.sub, 12, .medium, .white.withAlphaComponent(0.6)), main]
        if !atStart { views.append(label(item == nil ? "나중에 다시" : "다시 알려 줘요", 11, .bold, .white.withAlphaComponent(0.5))) }
        let chipViews: [NSView] = Self.chips.map { m in PillButton(Self.minutesText(m), primary: false) { snooze(m) } } + [
            PillButton(expanded ? "접기" : "직접 고르기", primary: false) { [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                Self.current = TaskAlertPanel(n, petFrame, v, expanded: !expanded)
            }]
        let chipRow = NSStackView(views: chipViews); chipRow.spacing = 6; chipRow.distribution = .fillProportionally
        if !atStart { views.append(chipRow) }
        if expanded && !atStart {
            let wheel = WheelPicker(values: Self.wheelValues.map(Self.minutesText), selected: 3)
            let confirm = PillButton("\(Self.minutesText(Self.wheelValues[3])) 뒤 알림", primary: true) { snooze(Self.wheelValues[wheel.selected]) }
            wheel.onChange = { [weak confirm] i in confirm?.setTitle("\(Self.minutesText(Self.wheelValues[i])) 뒤 알림") }
            wheel.translatesAutoresizingMaskIntoConstraints = false
            wheel.widthAnchor.constraint(equalToConstant: w - 40).isActive = true
            wheel.heightAnchor.constraint(equalToConstant: 130).isActive = true
            confirm.heightAnchor.constraint(equalToConstant: 34).isActive = true
            confirm.widthAnchor.constraint(equalToConstant: w - 40).isActive = true
            views += [wheel, confirm]
        }
        if isEvent && !atStart { views.append(label("알림을 끄지 않으면 시작할 때 한 번 더 알려 줘요", 10, .medium, .white.withAlphaComponent(0.45))) }
        if !next.isEmpty {
            let sep = NSBox(); sep.boxType = .separator
            views.append(sep)
            views.append(label("다음", 11, .semibold, .white.withAlphaComponent(0.5)))
            views += next.map { label($0.title, 13, .medium, .white) }
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.setCustomSpacing(14, after: views[2])
        stack.setCustomSpacing(12, after: main)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.frame = root.bounds; stack.autoresizingMask = [.width, .height]
        for v in views { v.widthAnchor.constraint(lessThanOrEqualToConstant: w - 40).isActive = true }
        main.widthAnchor.constraint(equalToConstant: w - 40).isActive = true
        main.heightAnchor.constraint(equalToConstant: 36).isActive = true
        chipRow.widthAnchor.constraint(equalToConstant: w - 40).isActive = true
        chipViews.forEach { $0.heightAnchor.constraint(equalToConstant: 28).isActive = true }
        root.addSubview(stack)
        panel.contentView = root
        panel.orderFrontRegardless()
        // 고르는 중(펼침)에는 저절로 닫지 않는다
        if !expanded { Ticker.once("할 일 알림 닫기", 60) { [weak self] _ in self?.close(next: true) } }
    }

    private func close(next: Bool) {
        panel.orderOut(nil)
        guard Self.current === self else { return }
        Self.current = nil
        if next, !Self.queue.isEmpty {
            let (n, f, v) = Self.queue.removeFirst()
            Self.current = TaskAlertPanel(n, f, v)
        }
    }
}

/// F27 둥근 버튼(파랑 = 주 동작, 유리 = 보조). 포커스를 받지 않는다.
final class PillButton: NSButton {
    private let handler: () -> Void
    init(_ title: String, primary: Bool, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        isBordered = false; wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = (primary ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.12)).cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        refusesFirstResponder = true
        target = self; action = #selector(run)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
    func setTitle(_ t: String) { attributedTitle = NSAttributedString(string: t, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]) }
}

/// F28 굴리는 고르기(아이폰 휠처럼): 스크롤·끌기·누르기로 고르고, 가운데 줄이 고른 값
final class WheelPicker: NSView {
    let values: [String]
    private(set) var selected: Int { didSet { if selected != oldValue { needsDisplay = true; onChange(selected) } } }
    var onChange: (Int) -> Void = { _ in }
    private var acc: CGFloat = 0, dragY: CGFloat?
    private let rowH: CGFloat = 26
    init(values: [String], selected: Int) { self.values = values; self.selected = selected; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with e: NSEvent) {
        acc += e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 10)
        while abs(acc) >= rowH { step(acc > 0 ? -1 : 1); acc -= acc > 0 ? rowH : -rowH }
    }
    override func mouseDown(with e: NSEvent) { dragY = convert(e.locationInWindow, from: nil).y }
    override func mouseDragged(with e: NSEvent) {
        let y = convert(e.locationInWindow, from: nil).y
        guard let d = dragY, abs(y - d) >= rowH else { return }
        step(y > d ? 1 : -1); dragY = y
    }
    override func mouseUp(with e: NSEvent) {
        defer { dragY = nil }
        let y = convert(e.locationInWindow, from: nil).y
        guard let d = dragY, abs(y - d) < 3 else { return }
        step(Int(((bounds.midY - y) / rowH).rounded()))   // 누른 줄로
    }
    private func step(_ k: Int) { selected = min(max(selected + k, 0), values.count - 1) }
    override func draw(_ dirtyRect: NSRect) {
        let band = CGRect(x: 0, y: bounds.midY - rowH / 2, width: bounds.width, height: rowH)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: band, xRadius: 9, yRadius: 9).fill()
        let para = NSMutableParagraphStyle(); para.alignment = .center
        for k in -2...2 {
            let i = selected + k
            guard values.indices.contains(i) else { continue }
            let on = k == 0
            let s = NSAttributedString(string: values[i], attributes: [.font: NSFont.systemFont(ofSize: on ? 17 : 13, weight: on ? .heavy : .medium),
                                                                       .foregroundColor: NSColor.white.withAlphaComponent(on ? 1 : 0.35 - 0.1 * CGFloat(abs(k) - 1)), .paragraphStyle: para])
            let hgt = s.size().height
            s.draw(in: CGRect(x: 0, y: bounds.midY - CGFloat(k) * rowH - hgt / 2, width: bounds.width, height: hgt))
        }
    }
}

// MARK: - 보기·입력 창

final class TaskWindow: NSObject, NSTextFieldDelegate {
    static let shared = TaskWindow()
    private var panel: FloatingPanel?
    private let input = NSTextField()
    private let chips = NSStackView()
    private let list = NSStackView()
    /// F27 6번 A: 오른쪽 '다가오는' 칸
    private let list2 = NSStackView()
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?
    /// 지금 입력의 날짜(칩으로 고치면 `manual`)
    private var parsed = QuickParse.Result(title: "", date: nil, hasTime: false)
    private var manual: (date: Date?, hasTime: Bool)?
    private var asEvent = true
    private var popover: NSPopover?
    private static let width: CGFloat = 620, height: CGFloat = 500
    private static let column: CGFloat = (width - 30) / 2
    /// F26 H: 큰 제목·진행 막대·탭·아래 입력
    private let heading = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let progressText = NSTextField(labelWithString: "")
    private let colTitles = (NSTextField(labelWithString: "오늘"), NSTextField(labelWithString: "다가오는"))

    static func timeText(_ d: Date, hasTime: Bool) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR")
        let cal = Calendar.current
        let day = cal.isDateInToday(d) ? "오늘" : cal.isDateInTomorrow(d) ? "내일" : { f.dateFormat = "M/d(E)"; return f.string(from: d) }()
        guard hasTime else { return day }
        f.dateFormat = "a h:mm"
        return "\(day) \(f.string(from: d))"
    }

    func toggle() { panel == nil ? open() : close(restore: true) }

    func open() {
        guard panel == nil else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let w = Self.width, h = Self.height
        let p = FloatingPanel(size: CGSize(width: w, height: h))
        p.keyable = true
        p.level = .popUpMenu
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        p.setFrameOrigin(CGPoint(x: v.midX - w / 2, y: v.maxY - v.height / 3 - h / 2))

        let effect = EscapableEffectView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        effect.material = .hudWindow; effect.state = .active
        effect.wantsLayer = true; effect.layer?.cornerRadius = 14; effect.layer?.masksToBounds = true
        effect.onEscape = { [weak self] in self?.close(restore: true) }

        heading.frame = CGRect(x: 16, y: h - 46, width: w - 32, height: 30)
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        effect.addSubview(heading)
        progress.frame = CGRect(x: 16, y: h - 66, width: w - 110, height: 12)
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        effect.addSubview(progress)
        progressText.frame = CGRect(x: w - 90, y: h - 68, width: 74, height: 16)
        progressText.font = .systemFont(ofSize: 11); progressText.textColor = .secondaryLabelColor; progressText.alignment = .right
        effect.addSubview(progressText)
        // F27 6번 C: '고정'을 누르면 항상 위 미니 창으로
        let pin = ClosureButton("") { [weak self] in self?.close(restore: true); TaskMini.shared.show() }
        pin.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "고정")
        pin.bezelStyle = .inline; pin.toolTip = "항상 위 작은 창으로 고정"
        pin.frame = CGRect(x: w - 44, y: h - 42, width: 28, height: 22)
        effect.addSubview(pin)
        for (i, t) in [colTitles.0, colTitles.1].enumerated() {
            t.font = .boldSystemFont(ofSize: 13); t.textColor = .secondaryLabelColor
            t.frame = CGRect(x: 14 + CGFloat(i) * (Self.column + 4), y: h - 98, width: Self.column, height: 18)
            effect.addSubview(t)
        }

        input.frame = CGRect(x: 12, y: 10, width: w - 24, height: 30)
        input.placeholderString = "예: 내일 3시 치과 · ↩ 추가 · Esc 닫기"
        input.font = .systemFont(ofSize: 15)
        input.stringValue = ""
        input.delegate = self
        input.bezelStyle = .roundedBezel
        effect.addSubview(input)

        chips.frame = CGRect(x: 12, y: 44, width: w - 24, height: 26)
        chips.orientation = .horizontal; chips.spacing = 6
        effect.addSubview(chips)

        for (i, l) in [list, list2].enumerated() {
            let scroll = NSScrollView(frame: CGRect(x: 6 + CGFloat(i) * (Self.column + 4), y: 76, width: Self.column + 8, height: h - 184))
            scroll.drawsBackground = false; scroll.hasVerticalScroller = true
            scroll.wantsLayer = true; scroll.layer?.cornerRadius = 12
            scroll.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
            l.orientation = .vertical; l.alignment = .leading; l.spacing = 2
            l.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
            let doc = FlippedView(frame: CGRect(x: 0, y: 0, width: Self.column - 8, height: 10))
            doc.addSubview(l)
            scroll.documentView = doc
            effect.addSubview(scroll)
        }
        p.contentView = effect
        panel = p
        parsed = .init(title: "", date: nil, hasTime: false); manual = nil; dateRemoved = false
        updateChips()
        reload()

        NSApp.activate(ignoringOtherApps: true)   // 바로 입력할 수 있게(사용자가 직접 연 창)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(input)
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close(restore: false) },
        ].compactMap { $0 }
        TaskStore.shared.onChange = { [weak self] in self?.reload() }
        TaskStore.shared.reload()
    }

    func close(restore: Bool) {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        popover?.close(); popover = nil
        panel?.orderOut(nil); panel = nil
        TaskStore.shared.onChange = {}
        if restore { previousApp?.activate() }
    }

    // 입력
    func controlTextDidChange(_ obj: Notification) {
        parsed = QuickParse.parse(input.stringValue)
        updateChips()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { submit(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { close(restore: true); return true }
        return false
    }

    /// ✕로 날짜를 뺐으면 날짜 말도 제목에 남긴다
    private var dateRemoved = false
    private var current: (date: Date?, hasTime: Bool) { manual ?? (parsed.date, parsed.hasTime) }

    private func submit() {
        guard !input.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let c = current
        let event = asEvent && c.hasTime && TaskStore.shared.canAddEvent
        let title = dateRemoved ? input.stringValue.trimmingCharacters(in: .whitespaces) : parsed.title
        if let problem = TaskStore.shared.add(title: title, date: c.date, hasTime: c.hasTime, asEvent: event) {
            NSSound.beep()
            updateChips(message: problem)
        } else {
            input.stringValue = ""; parsed = .init(title: "", date: nil, hasTime: false); manual = nil; dateRemoved = false
            updateChips()
        }
    }

    private func updateChips(message: String? = nil) {
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let message {
            let f = NSTextField(labelWithString: message)
            f.font = .systemFont(ofSize: 11); f.textColor = .systemRed; f.lineBreakMode = .byTruncatingTail
            chips.addArrangedSubview(f)
            return
        }
        let c = current
        if let d = c.date {
            let chip = ClosureButton("📅 " + Self.timeText(d, hasTime: c.hasTime)) {}
            chip.handler = { [weak self, weak chip] in if let chip { self?.editDate(from: chip) } }
            chips.addArrangedSubview(chip)
            chips.addArrangedSubview(ClosureButton("✕") { [weak self] in self?.manual = (nil, false); self?.dateRemoved = true; self?.updateChips() })
        } else if !input.stringValue.isEmpty {
            chips.addArrangedSubview(ClosureButton("날짜 넣기") { [weak self] in
                guard let self else { return }
                self.manual = (Calendar.current.startOfDay(for: Date()), false); self.updateChips()
            })
        }
        // 시간이 있을 때만 할 일/일정을 고를 수 있다
        if c.hasTime, TaskStore.shared.canAddEvent, TaskStore.shared.canAddReminder {
            let seg = NSSegmentedControl(labels: ["일정", "할 일"], trackingMode: .selectOne, target: self, action: #selector(kindChanged(_:)))
            seg.controlSize = .small
            seg.selectedSegment = asEvent ? 0 : 1
            chips.addArrangedSubview(seg)
        }
    }

    @objc private func kindChanged(_ s: NSSegmentedControl) { asEvent = s.selectedSegment == 0 }

    private func editDate(from chip: NSView) {
        let c = current
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = c.hasTime ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        picker.dateValue = c.date ?? Date()
        picker.sizeToFit()
        let timeOn = ClosureButton("시간") {}
        timeOn.setButtonType(.switch)
        timeOn.handler = { [weak picker, weak timeOn] in
            picker?.datePickerElements = timeOn?.state == .on ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        }
        timeOn.state = c.hasTime ? .on : .off
        let box = NSStackView(views: [picker, timeOn])
        box.orientation = .vertical; box.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        box.frame.size = box.fittingSize
        let vc = NSViewController(); vc.view = box
        let pop = NSPopover(); pop.contentViewController = vc; pop.behavior = .transient
        let apply = ClosureButton("확인") { [weak self, weak picker, weak timeOn, weak pop] in
            guard let picker, let timeOn else { return }
            let on = timeOn.state == .on
            self?.manual = (on ? picker.dateValue : Calendar.current.startOfDay(for: picker.dateValue), on)
            self?.updateChips(); pop?.close()
        }
        box.addArrangedSubview(apply)
        box.frame.size = box.fittingSize
        popover = pop
        pop.show(relativeTo: chip.bounds, of: chip, preferredEdge: .maxY)
    }

    // 목록
    private func reload() {
        guard list.superview != nil else { return }
        [list, list2].forEach { $0.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        let store = TaskStore.shared
        if !store.canAddReminder && !store.canAddEvent {
            list.addArrangedSubview(note(TaskStore.anyOn ? "권한이 필요해요. 설정 '할 일·일정'에서 권한을 열어 주세요." : "설정 '할 일·일정'에서 켜 주세요."))
        }
        let g = TaskLogic.groups(store.items, now: Date())
        let left = TaskLogic.pending(store.items, now: Date()).count
        heading.stringValue = left == 0 ? "오늘 할 일을 다 했어요" : "할 일 \(left)개 남았어요"
        let p = TaskLogic.progress(done: store.doneToday, left: g.today.filter { !$0.isEvent }.count)
        progress.doubleValue = p.fraction; progressText.stringValue = p.text
        // 왼쪽: 오늘 + 날짜 없음, 오른쪽: 다가오는 일
        colTitles.0.stringValue = "오늘 \(g.today.count + g.undated.count)"
        colTitles.1.stringValue = "다가오는 \(g.upcoming.count)"
        func fill(_ l: NSStackView, _ groups: [(String?, [TaskItem])], empty: String) {
            if groups.allSatisfy({ $0.1.isEmpty }) { l.addArrangedSubview(note(empty)) }
            for (name, items) in groups where !items.isEmpty {
                if let name {
                    let h = NSTextField(labelWithString: name)
                    h.font = .boldSystemFont(ofSize: 11); h.textColor = .tertiaryLabelColor
                    l.addArrangedSubview(h)
                }
                items.forEach { l.addArrangedSubview(row($0)) }
            }
            guard let doc = l.superview else { return }
            let size = l.fittingSize, width = Self.column - 8
            doc.frame.size = CGSize(width: width, height: max(size.height, 10))
            l.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        }
        fill(list, [(nil, g.today), ("날짜 없음", g.undated)], empty: "비어 있어요. 아래에 적고 ↩를 누르면 추가돼요.")
        fill(list2, [(nil, g.upcoming)], empty: "다가오는 일이 없어요.")
    }

    /// 두 번 눌러 고치기: 이름 + 날짜(시간 켜기·끄기, 날짜 빼기)
    var isEditing: Bool { popover?.isShown == true }

    func edit(_ item: TaskItem, from row: NSView) {
        popover?.close()
        let name = NSTextField(string: item.title)
        name.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let hasDate = ClosureButton("날짜") {}
        hasDate.setButtonType(.switch)
        hasDate.state = item.date == nil ? .off : .on
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = item.hasTime ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        picker.dateValue = item.date ?? Date()
        picker.isHidden = item.date == nil
        let timeOn = ClosureButton("시간") {}
        timeOn.setButtonType(.switch)
        timeOn.state = item.hasTime ? .on : .off
        timeOn.isHidden = item.date == nil
        timeOn.handler = { [weak picker, weak timeOn] in
            picker?.datePickerElements = timeOn?.state == .on ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        }
        hasDate.isHidden = item.isEvent   // 일정은 날짜를 뺄 수 없다
        let problem = NSTextField(labelWithString: "")
        problem.font = .systemFont(ofSize: 11); problem.textColor = .systemRed; problem.isHidden = true
        let box = NSStackView(views: [name, hasDate, picker, timeOn, problem])
        box.orientation = .vertical; box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let vc = NSViewController(); vc.view = box
        let pop = NSPopover(); pop.contentViewController = vc; pop.behavior = .transient
        func fit() { box.frame.size = box.fittingSize; pop.contentSize = box.fittingSize }
        hasDate.handler = { [weak picker, weak timeOn] in
            let on = hasDate.state == .on
            picker?.isHidden = !on; timeOn?.isHidden = !on
            fit()
        }
        let save = ClosureButton("저장") { [weak pop, weak name, weak picker, weak timeOn, weak problem] in
            guard let name, let picker, let timeOn else { return }
            let dated = hasDate.state == .on, timed = dated && timeOn.state == .on
            let date = dated ? (timed ? picker.dateValue : Calendar.current.startOfDay(for: picker.dateValue)) : nil
            if let msg = TaskStore.shared.update(item, title: name.stringValue.trimmingCharacters(in: .whitespaces), date: date, hasTime: timed) {
                problem?.stringValue = msg; problem?.isHidden = false; fit()
            } else { pop?.close() }
        }
        save.keyEquivalent = "\r"
        box.addArrangedSubview(save)
        fit()
        popover = pop
        pop.show(relativeTo: row.bounds, of: row, preferredEdge: .maxX)
        pop.contentViewController?.view.window?.makeFirstResponder(name)
    }

    private func confirmDelete(_ item: TaskItem) {
        let a = NSAlert()
        a.messageText = "'\(item.title)'을(를) 지울까요?"
        a.informativeText = item.isEvent ? "캘린더에서 지워지고 되돌릴 수 없어요." : "미리 알림에서 지워지고 되돌릴 수 없어요."
        a.addButton(withTitle: "지우기"); a.addButton(withTitle: "취소")
        a.buttons[0].hasDestructiveAction = true
        guard let panel else { return }
        a.beginSheetModal(for: panel) { if $0 == .alertFirstButtonReturn { TaskStore.shared.delete(item) } }
    }

    private func note(_ t: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: t); f.font = .systemFont(ofSize: 12); f.textColor = .secondaryLabelColor
        return f
    }

    private func row(_ item: TaskItem) -> NSView {
        let overdue = (item.date.map { item.hasTime ? $0 < Date() : $0 < Calendar.current.startOfDay(for: Date()) } ?? false) && !item.isEvent
        let lead: NSView = item.isEvent
            ? NSImageView(image: NSImage(systemSymbolName: "calendar", accessibilityDescription: "일정")!)
            : { let b = ClosureButton("") { TaskStore.shared.complete(item) }; b.setButtonType(.switch); return b }()
        let title = NSTextField(labelWithString: item.title)
        title.lineBreakMode = .byTruncatingTail
        title.widthAnchor.constraint(lessThanOrEqualToConstant: Self.column - 130).isActive = true
        let time = NSTextField(labelWithString: item.date.map { Self.timeText($0, hasTime: item.hasTime) } ?? "")
        time.font = .systemFont(ofSize: 11); time.textColor = overdue ? .systemRed : .secondaryLabelColor
        let r = MenuRow(views: [lead, title, time])
        r.spacing = 8
        // 지우면 되돌릴 수 없어서 한 번 더 묻는다. 바꿀 수 없는 캘린더(공휴일·구독)는 메뉴·고치기 없음
        if item.ref?.calendar.allowsContentModifications == true {
            r.menuItems = [("고치기…", { [weak self, weak r] in if let r { self?.edit(item, from: r) } }),
                           ("삭제…", { [weak self] in self?.confirmDelete(item) })]
            r.onDoubleClick = { [weak self, weak r] in if let r { self?.edit(item, from: r) } }
        }
        return r
    }
}

/// 오른쪽 클릭 메뉴가 있는 줄
final class MenuRow: NSStackView {
    var menuItems: [(String, () -> Void)] = []
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick { onDoubleClick() } else { super.mouseDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        menuItems.forEach { m.addItem(ClosureMenuItem($0.0, $0.1)) }
        return m
    }
}


/// F26: 할 일을 끝내면 화면 아래 가운데에 4초 동안 "끝냈어요 · 되돌리기"
final class DoneToast {
    private static var current: FloatingPanel?
    static func text(_ title: String) -> String { "‘\(title)’ 끝냈어요" }

    static func show(_ title: String, undo: @escaping () -> Void) {
        current?.orderOut(nil)
        let label = NSTextField(labelWithString: "✓ " + text(title))
        label.font = .systemFont(ofSize: 13, weight: .semibold); label.lineBreakMode = .byTruncatingTail
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        var panel: FloatingPanel?
        let back = ClosureButton("되돌리기") { undo(); panel?.orderOut(nil) }
        back.bezelStyle = .inline
        let stack = NSStackView(views: [label, back]); stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 10)
        let size = stack.fittingSize
        let p = FloatingPanel(size: size)
        let glass = makeGlass(cornerRadius: size.height / 2, frame: CGRect(origin: .zero, size: size))
        let root = NSView(frame: glass.frame); root.wantsLayer = true; root.layer?.cornerRadius = size.height / 2; root.layer?.masksToBounds = true
        root.addSubview(glass); stack.frame = root.bounds; root.addSubview(stack)
        p.contentView = root
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        p.setFrameOrigin(CGPoint(x: v.midX - size.width / 2, y: v.minY + 40))
        p.orderFrontRegardless()
        panel = p; current = p
        Ticker.once("완료 토스트 닫기", 4) { _ in if current === p { p.orderOut(nil); current = nil } }
    }
}

/// F27 6번 C: 항상 위 작은 할 일 창(포커스를 뺏지 않음). 끌어서 옮기고, 자리는 기억한다. 고정 풀기를 누르면 큰 창으로.
final class TaskMini: NSObject {
    static let shared = TaskMini()
    private var panel: FloatingPanel?
    private let stack = NSStackView()
    var isOpen: Bool { panel != nil }

    func show() {
        guard panel == nil else { return }
        let w: CGFloat = 260
        let p = FloatingPanel(size: CGSize(width: w, height: 120))
        p.appearance = NSAppearance(named: .darkAqua)
        p.isMovable = true; p.isMovableByWindowBackground = true
        let v = NSScreen.main?.visibleFrame ?? .zero
        let saved = UserDefaults.standard.string(forKey: "taskMiniOrigin").map(NSPointFromString)
        p.setFrameOrigin(saved ?? CGPoint(x: v.maxX - w - 16, y: v.maxY - 200))
        let root = NSView(frame: p.frame)
        let glass = makeGlass(cornerRadius: 16, frame: root.bounds)
        glass.autoresizingMask = [.width, .height]
        root.addSubview(glass)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.frame = root.bounds; stack.autoresizingMask = [.width, .height]
        root.addSubview(stack)
        p.contentView = root
        p.orderFrontRegardless()
        panel = p
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: TaskStore.changedNote, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: p)
        refresh()
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        panel?.orderOut(nil); panel = nil
    }

    @objc private func moved() { if let p = panel { UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "taskMiniOrigin") } }

    @objc private func refresh() {
        guard let p = panel else { return }
        let pending = TaskLogic.pending(TaskStore.shared.items, now: Date())
        let title = NSTextField(labelWithString: pending.isEmpty ? "오늘 할 일을 다 했어요" : "오늘 할 일 \(pending.count)")
        title.font = .boldSystemFont(ofSize: 14); title.textColor = .white
        let unpin = ClosureButton("") { [weak self] in self?.close(); TaskWindow.shared.open() }
        unpin.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "고정 풀기")
        unpin.bezelStyle = .inline; unpin.toolTip = "고정 풀기(큰 창으로)"
        let head = NSStackView(views: [title, NSView(), unpin])
        head.translatesAutoresizingMaskIntoConstraints = false
        head.widthAnchor.constraint(equalToConstant: p.frame.width - 28).isActive = true
        var views: [NSView] = [head]
        for item in pending.prefix(8) {
            let b = ClosureButton(item.title) { TaskStore.shared.complete(item) }
            b.setButtonType(.switch); b.font = .systemFont(ofSize: 13)
            b.lineBreakMode = .byTruncatingTail
            b.widthAnchor.constraint(lessThanOrEqualToConstant: p.frame.width - 28).isActive = true
            views.append(b)
        }
        if pending.count > 8 { let more = NSTextField(labelWithString: "외 \(pending.count - 8)개"); more.font = .systemFont(ofSize: 11); more.textColor = .secondaryLabelColor; views.append(more) }
        stack.setViews(views, in: .leading)
        let h = stack.fittingSize.height
        var f = p.frame
        f.origin.y += f.height - h; f.size.height = h
        p.setFrame(f, display: true)
    }
}
