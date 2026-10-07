import '../models/document.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';

class SampleData {
  static List<Document> getInitialDocuments() {
    return [
      Document(
        id: 'doc-1',
        name: 'Q3 financial report.pdf',
        pageCount: 42,
        uploadDate: DateTime(2026, 9, 24),
        status: DocumentStatus.ready,
        progress: 1.0,
        pages: [
          '''Q3 FINANCIAL PERFORMANCE SUMMARY
Executive Overview - Fiscal Year 2026

1. Highlights & Revenue Drivers:
• Total Consolidated Revenue: \$48.2M (+14.2% YoY growth).
• Gross Margin expanded 180 bps to 68.4%.
• Subscription ARR grew to \$38.6M, representing 80% of top-line mix.
• Operating Cash Flow generated: \$11.4M for the quarter.

2. Segment Performance:
• Enterprise Cloud: \$27.1M (up 22% YoY) driven by expansion in North America and EMEA.
• Mid-Market Services: \$15.3M (steady 6% YoY growth).
• Professional Services & Advisory: \$5.8M.

3. Expense Breakdown:
• Research & Development: \$14.2M (29.4% of revenue).
• Sales & Marketing: \$16.8M (34.8% of revenue).
• General & Administrative: \$6.1M (12.6% of revenue).
• Adjusted EBITDA: \$11.1M (23.0% margin).''',
          '''Q3 FINANCIAL REPORT - BALANCE SHEET & CASH FLOW

Assets & Liquidity Position:
• Cash and Cash Equivalents: \$94.5M (compared to \$83.1M in Q2).
• Marketable Securities: \$22.0M.
• Accounts Receivable (Net): \$18.4M (DSO: 41 days).
• Total Current Assets: \$134.9M.

Liabilities & Shareholders' Equity:
• Current Liabilities: \$24.1M.
• Deferred Revenue (Current): \$31.8M.
• Long-Term Debt: \$0 (Zero debt obligations).
• Total Shareholders' Equity: \$152.6M.

Forward Outlook & Guidance:
• Q4 Revenue expected between \$51.0M - \$53.5M.
• Full Year Revenue upgraded to \$188M - \$192M.''',
        ],
      ),
      Document(
        id: 'doc-2',
        name: 'Lease agreement.pdf',
        pageCount: 18,
        uploadDate: DateTime(2026, 9, 22),
        status: DocumentStatus.ready,
        progress: 1.0,
        pages: [
          '''RESIDENTIAL LEASE AGREEMENT
Standard Term & Conditions - Suite 402, Oakwood Residences

PARTIES AND PREMISES:
This Lease Agreement (the "Agreement") is entered into between Oakwood Property Holdings LLC ("Landlord") and the Tenant.

1. LEASE TERM & COMMENCEMENT:
• Commencement Date: April 1, 2024.
• Initial Expiration Date: March 31, 2027.
• Notice of Non-Renewal: At least 60 calendar days written notice prior to term expiration.

2. RENT AMOUNT & SCHEDULED ESCALATION:
• Base Rent: \$1,850.00 payable on the first day of each calendar month.
• Scheduled Renewal Increase: 4.0% annual adjustment upon renewal term.
• Adjusted Monthly Rent at Renewal: \$1,924.00 per month.
• Late Fee: \$50.00 after the 5th calendar day of the month.''',
          '''RESIDENTIAL LEASE AGREEMENT - PAGE 2 OF 18

3. SECURITY DEPOSIT & ESCROW:
• Deposit Sum: \$1,850.00 held in an interest-bearing escrow account at First Horizon Bank.
• Return Period: Within 30 days of lease termination and premises vacancy inspection.

4. MAINTENANCE, UTILITIES & REPAIRS:
• Landlord Responsibilities: Structural repairs, exterior roof, HVAC primary systems, water/sewer base connection.
• Tenant Responsibilities: Electricity, high-speed internet, minor fixtures, keeping smoke alarms in operable status.

5. TERMINATION & DEFAULT CLAUSES:
• Breach of Terms: 14-day cure notice required for monetary or behavioral non-compliance.
• Early Termination Fee: Equivalent to two months' base rent plus forfeiture of security deposit if vacated prior to March 31, 2027.''',
        ],
      ),
      Document(
        id: 'doc-3',
        name: 'Research paper.pdf',
        pageCount: 28,
        uploadDate: DateTime(2026, 9, 26),
        status: DocumentStatus.processing,
        progress: 0.64,
        pages: [],
      ),
      Document(
        id: 'doc-4',
        name: 'Scan_0913.pdf',
        pageCount: 4,
        uploadDate: DateTime(2026, 9, 13),
        status: DocumentStatus.failed,
        progress: 0.0,
        errorMessage: "Couldn't read this file",
        pages: [],
      ),
    ];
  }

  static List<ChatSession> getInitialChatSessions() {
    final now = DateTime.now();
    return [
      ChatSession(
        id: 'chat-1',
        title: 'Lease end date and rent inc...',
        createdAt: now.subtract(const Duration(hours: 1)),
        scopeDocumentId: 'doc-2', // Lease agreement
        messages: [
          ChatMessage(
            id: 'm1',
            text: 'When does my lease end and what was the rent increase?',
            isUser: true,
            timestamp: now.subtract(const Duration(minutes: 15)),
          ),
          ChatMessage(
            id: 'm2',
            text:
                'Your lease ends on March 31, 2027.\n\nThe rent increases by 4% at renewal, taking it from \$1,850 to \$1,924 per month.',
            isUser: false,
            timestamp: now.subtract(const Duration(minutes: 14)),
            sourceFileNames: ['Lease agreement.pdf'],
          ),
        ],
      ),
      ChatSession(
        id: 'chat-2',
        title: 'Q3 revenue drivers',
        createdAt: now.subtract(const Duration(days: 1)),
        scopeDocumentId: 'doc-1', // Q3 report
        messages: [
          ChatMessage(
            id: 'm3',
            text: 'What were the main Q3 revenue drivers?',
            isUser: true,
            timestamp: now.subtract(const Duration(days: 1)),
          ),
          ChatMessage(
            id: 'm4',
            text:
                'Enterprise Cloud grew 22% YoY to \$27.1M, representing over 56% of total revenue. Subscription ARR also climbed to \$38.6M with gross margins expanding to 68.4%.',
            isUser: false,
            timestamp: now.subtract(const Duration(days: 1)),
            sourceFileNames: ['Q3 financial report.pdf'],
          ),
        ],
      ),
      ChatSession(
        id: 'chat-3',
        title: 'Summary of research methods',
        createdAt: now.subtract(const Duration(days: 3)),
        messages: [],
      ),
      ChatSession(
        id: 'chat-4',
        title: 'Termination clauses',
        createdAt: now.subtract(const Duration(days: 5)),
        messages: [],
      ),
      ChatSession(
        id: 'chat-5',
        title: 'Compare budget across reports',
        createdAt: now.subtract(const Duration(days: 7)),
        messages: [],
      ),
    ];
  }
}
