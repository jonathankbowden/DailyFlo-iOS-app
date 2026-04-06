//
//  PhaseModel.swift
//  DailyFlo
//
//  Created by Jonathan Bowden on 2/2/26.
//

import SwiftUI

// MARK: - Cycle Phase
enum CyclePhase: Int, CaseIterable {
    case menstrual = 1
    case follicular = 2
    case ovulation = 3
    case luteal = 4
    
    var name: String {
        switch self {
        case .menstrual: return "Menstrual Phase"
        case .follicular: return "Follicular Phase"
        case .ovulation: return "Ovulation Phase"
        case .luteal: return "Luteal Phase"
        }
    }
    
    var subtitle: String {
        switch self {
        case .menstrual: return "LOW HORMONE PHASE"
        case .follicular: return "HIGH ENERGY PHASE"
        case .ovulation: return "THE LOVE PHASE"
        case .luteal: return "YOUR HIGH HORMONE PHASE"
        }
    }
    
    var number: String {
        String(format: "%02d", self.rawValue)
    }
    
    var color: Color {
        switch self {
        case .menstrual: return .phaseMenstrual
        case .follicular: return .phaseFollicular
        case .ovulation: return .phaseOvulation
        case .luteal: return .phaseLuteal
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .menstrual: return Color(hex: "F5E6E6")
        case .follicular: return Color(hex: "E8F0E8")
        case .ovulation: return Color(hex: "FDF4E7")
        case .luteal: return Color(hex: "E8EEF2")
        }
    }
    
    // Typical day ranges in a 28-day cycle
    var dayRange: ClosedRange<Int> {
        switch self {
        case .menstrual: return 1...5
        case .follicular: return 6...13
        case .ovulation: return 14...16
        case .luteal: return 17...28
        }
    }
    
    static func phase(forDay day: Int) -> CyclePhase {
        let normalizedDay = ((day - 1) % 28) + 1
        for phase in CyclePhase.allCases {
            if phase.dayRange.contains(normalizedDay) {
                return phase
            }
        }
        return .menstrual
    }
}

// MARK: - Content Tab
enum PhaseContentTab: String, CaseIterable {
    case mind = "MIND"
    case body = "BODY"
    case soul = "SOUL"
}

// MARK: - Phase Content
struct PhaseContent {
    let phase: CyclePhase
    let tab: PhaseContentTab
    let title: String
    let content: String
    let imageName: String
    
    static func content(for phase: CyclePhase, tab: PhaseContentTab) -> PhaseContent {
        switch (phase, tab) {
        // MENSTRUAL
        case (.menstrual, .mind):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY MIND",
                content: "During menstruation, your hormone levels are at their lowest. This is a time for reflection and introspection. You may feel more introverted and prefer quiet activities. Honor this need for rest—your brain is processing and preparing for the cycle ahead.\n\nThis is an excellent time for journaling, meditation, and setting intentions for the month ahead.",
                imageName: "menstrual_mind"
            )
        case (.menstrual, .body):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY BODY",
                content: "Your body is shedding the uterine lining, which can cause cramping and fatigue. Energy levels are typically at their lowest point. Gentle movement like yoga or walking can help ease discomfort.\n\nFocus on nourishing foods rich in iron and stay hydrated. This is not the time to push your body—rest is productive.",
                imageName: "menstrual_body"
            )
        case (.menstrual, .soul):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY SOUL",
                content: "This phase invites surrender and release. Just as your body releases what it no longer needs, consider what emotional or mental patterns you're ready to let go of.\n\nMany women find this a deeply spiritual time. Create space for prayer, meditation, or simply being still. Trust the wisdom of your body's natural rhythm.",
                imageName: "menstrual_soul"
            )
            
        // FOLLICULAR
        case (.follicular, .mind):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY MIND DURING FOLLICULAR",
                content: "Estrogen starts to surge during the follicular phase, helping your menstrual symptoms subside. You'll experience a mood and energy boost as a result.\n\nThis is an excellent time for brainstorming, starting new projects, and creative thinking. Your brain is primed for novelty and learning.",
                imageName: "follicular_mind"
            )
        case (.follicular, .body):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY BODY DURING FOLLICULAR",
                content: "Estrogen starts to surge during the follicular phase, helping your menstrual symptoms subside. You'll experience a mood and energy boost as a result.\n\nYour testosterone levels will be on the rise, too, stimulating your libido. With this renewed energy, you can participate in more physical activities. Intimacy with your partner is enjoyable in this phase.\n\nThe follicular phase brings about a lower basal body temperature.",
                imageName: "follicular_body"
            )
        case (.follicular, .soul):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY SOUL DURING FOLLICULAR",
                content: "This is a time of new beginnings and fresh starts. Like spring after winter, your spirit is ready to bloom. Plant seeds of intention and watch them grow.\n\nYou may feel more optimistic and open to possibilities. Use this energy to connect with your deeper purpose and take inspired action.",
                imageName: "follicular_soul"
            )
            
        // OVULATION
        case (.ovulation, .mind):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY MIND DURING OVULATION",
                content: "Your communication skills peak during ovulation. This is the ideal time for important conversations, presentations, or negotiations. You'll find words come easily and you're more persuasive.\n\nSocial energy is high—you may crave connection and community.",
                imageName: "ovulation_mind"
            )
        case (.ovulation, .body):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY BODY DURING OVULATION",
                content: "This is your peak fertility window. Estrogen and testosterone are at their highest, giving you maximum energy and confidence. You may notice increased libido and feel most attractive.\n\nYour body temperature rises slightly after ovulation. This is a great time for high-intensity workouts.",
                imageName: "ovulation_body"
            )
        case (.ovulation, .soul):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY SOUL DURING OVULATION",
                content: "The ovulation phase is about giving and receiving love. Your heart is open, and you may feel called to nurture others. This is a beautiful time for deepening relationships.\n\nChannel this loving energy into acts of service, quality time with loved ones, or creative expression that comes from the heart.",
                imageName: "ovulation_soul"
            )
            
        // LUTEAL
        case (.luteal, .mind):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY MIND DURING LUTEAL",
                content: "As progesterone rises, you may feel more detail-oriented and focused on completing tasks. This is an excellent time for editing, organizing, and finishing projects.\n\nYou might also notice increased sensitivity to your environment. Honor your need for boundaries.",
                imageName: "luteal_mind"
            )
        case (.luteal, .body):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY BODY DURING LUTEAL",
                content: "Progesterone dominates this phase, which can bring PMS symptoms like bloating, breast tenderness, and mood changes. Your metabolism increases, so you may feel hungrier.\n\nGentle exercise and stress management are key. Listen to your body's cues for rest.",
                imageName: "luteal_body"
            )
        case (.luteal, .soul):
            return PhaseContent(
                phase: phase,
                tab: tab,
                title: "MY SOUL DURING LUTEAL",
                content: "The luteal phase offers heightened intuition and discernment. You may see truth more clearly now—both in yourself and others. Use this clarity wisely.\n\nThis is a time of inner work. What needs to be released before your next cycle begins? Journal, reflect, and prepare for renewal.",
                imageName: "luteal_soul"
            )
        }
    }
}
