import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/constants/payment_terms.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../invoices/presentation/providers/template_providers.dart';
import '../providers/profile_provider.dart';

const _passphraseKey = 'backup_passphrase';

/// Reads the stored backup passphrase (or null if not set).
final backupPassphraseProvider = FutureProvider<String?>((ref) {
  return ref.watch(appSettingsDaoProvider).getValue(_passphraseKey);
});

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final UserProfile profile;
  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Profile Header ──────────────────────────────────────
        _ProfileHeader(profile: profile),
        const SizedBox(height: 24),

        // ── Identity ────────────────────────────────────────────
        _SectionLabel(label: 'Identity', icon: Icons.badge_outlined),
        _BusinessInfoTile(profile: profile),
        _TaxInfoTile(profile: profile),
        const SizedBox(height: 16),

        // ── Payments ────────────────────────────────────────────
        _SectionLabel(label: 'Payments', icon: Icons.account_balance_outlined),
        _BankDetailsTile(profile: profile),
        _PaymentLinksTile(profile: profile),
        const SizedBox(height: 16),

        // ── Preferences ─────────────────────────────────────────
        _SectionLabel(label: 'Preferences', icon: Icons.tune_outlined),
        _DefaultsTile(profile: profile),
        _InvoiceSettingsTile(profile: profile),
        _BackupTile(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Profile Header
// ─────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  const _ProfileHeader({required this.profile});

  int _completionPercent() {
    int filled = 0;
    int total = 7;
    if (profile.businessName.isNotEmpty) filled++;
    if (profile.ownerName.isNotEmpty) filled++;
    if (profile.email != null && profile.email!.isNotEmpty) filled++;
    if (profile.phone != null && profile.phone!.isNotEmpty) filled++;
    if (profile.addressLine1 != null && profile.addressLine1!.isNotEmpty) {
      filled++;
    }
    if (profile.bankName != null && profile.bankName!.isNotEmpty) filled++;
    if (profile.defaultHourlyRate > 0) filled++;
    return ((filled / total) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = _completionPercent();
    final initial = profile.businessName.isNotEmpty
        ? profile.businessName[0].toUpperCase()
        : '?';

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Avatar / Logo placeholder
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primary,
              child: profile.logoPath != null
                  ? ClipOval(
                      child: Image.asset(profile.logoPath!,
                          width: 64, height: 64, fit: BoxFit.cover),
                    )
                  : Text(initial,
                      style: theme.textTheme.headlineMedium?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.businessName.isNotEmpty
                        ? profile.businessName
                        : 'Your Business',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile.ownerName.isNotEmpty)
                    Text(profile.ownerName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  // Completion bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            minHeight: 6,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$pct%',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section Label
// ─────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Reusable expansion card
// ─────────────────────────────────────────────────────────────────────

class _ProfileExpansionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final bool isConfigured;
  final List<Widget> children;

  const _ProfileExpansionCard({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.isConfigured,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        title: Row(
          children: [
            Expanded(child: Text(title)),
            if (isConfigured)
              Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Set up',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer)),
              ),
          ],
        ),
        subtitle: Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 1. Business Info
// ─────────────────────────────────────────────────────────────────────

class _BusinessInfoTile extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _BusinessInfoTile({required this.profile});

  @override
  ConsumerState<_BusinessInfoTile> createState() => _BusinessInfoTileState();
}

class _BusinessInfoTileState extends ConsumerState<_BusinessInfoTile> {
  late final TextEditingController _businessName;
  late final TextEditingController _ownerName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _addr1;
  late final TextEditingController _addr2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _postal;
  late final TextEditingController _country;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _businessName = TextEditingController(text: p.businessName);
    _ownerName = TextEditingController(text: p.ownerName);
    _email = TextEditingController(text: p.email ?? '');
    _phone = TextEditingController(text: p.phone ?? '');
    _addr1 = TextEditingController(text: p.addressLine1 ?? '');
    _addr2 = TextEditingController(text: p.addressLine2 ?? '');
    _city = TextEditingController(text: p.city ?? '');
    _state = TextEditingController(text: p.stateProvince ?? '');
    _postal = TextEditingController(text: p.postalCode ?? '');
    _country = TextEditingController(text: p.country ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _businessName, _ownerName, _email, _phone,
      _addr1, _addr2, _city, _state, _postal, _country,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    await ref.read(profileNotifierProvider.notifier).updateBusinessInfo(
          businessName: _businessName.text.trim(),
          ownerName: _ownerName.text.trim(),
          email: _t(_email),
          phone: _t(_phone),
          addressLine1: _t(_addr1),
          addressLine2: _t(_addr2),
          city: _t(_city),
          stateProvince: _t(_state),
          postalCode: _t(_postal),
          country: _t(_country),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business info saved')));
    }
  }

  String _subtitle() {
    final parts = <String>[];
    if (widget.profile.email != null) parts.add(widget.profile.email!);
    if (widget.profile.phone != null) parts.add(widget.profile.phone!);
    if (parts.isEmpty) return 'Name, contact, address';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.profile.businessName.isNotEmpty &&
        widget.profile.ownerName.isNotEmpty;

    return _ProfileExpansionCard(
      title: 'Business Info',
      icon: Icons.storefront_outlined,
      subtitle: _subtitle(),
      isConfigured: configured,
      children: [
        const SizedBox(height: 8),
        TextFormField(
          controller: _businessName,
          decoration: const InputDecoration(
            labelText: 'Business Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _ownerName,
          decoration: const InputDecoration(
            labelText: 'Owner Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addr1,
          decoration: const InputDecoration(
            labelText: 'Address Line 1',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addr2,
          decoration: const InputDecoration(
            labelText: 'Address Line 2',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _city,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _state,
                decoration: const InputDecoration(
                  labelText: 'State',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _postal,
                decoration: const InputDecoration(
                  labelText: 'Postal Code',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _country,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 2. Tax Info
// ─────────────────────────────────────────────────────────────────────

class _TaxInfoTile extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _TaxInfoTile({required this.profile});

  @override
  ConsumerState<_TaxInfoTile> createState() => _TaxInfoTileState();
}

class _TaxInfoTileState extends ConsumerState<_TaxInfoTile> {
  late final TextEditingController _taxId;
  late final TextEditingController _waLicense;
  late bool _showTaxId;
  late bool _showWaLicense;

  @override
  void initState() {
    super.initState();
    _taxId = TextEditingController(text: widget.profile.taxId ?? '');
    _waLicense =
        TextEditingController(text: widget.profile.waBusinessLicense ?? '');
    _showTaxId = widget.profile.showTaxId;
    _showWaLicense = widget.profile.showWaLicense;
  }

  @override
  void dispose() {
    _taxId.dispose();
    _waLicense.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final tid = _taxId.text.trim();
    final wal = _waLicense.text.trim();
    await ref.read(profileNotifierProvider.notifier).updateTaxInfo(
          taxId: tid.isEmpty ? null : tid,
          showTaxId: _showTaxId,
          waBusinessLicense: wal.isEmpty ? null : wal,
          showWaLicense: _showWaLicense,
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tax info saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTaxId =
        widget.profile.taxId != null && widget.profile.taxId!.isNotEmpty;

    return _ProfileExpansionCard(
      title: 'Tax Information',
      icon: Icons.receipt_long_outlined,
      subtitle: hasTaxId ? 'Tax ID: ${widget.profile.taxId}' : 'EIN, VAT, licenses',
      isConfigured: hasTaxId,
      children: [
        const SizedBox(height: 8),
        TextFormField(
          controller: _taxId,
          decoration: const InputDecoration(
            labelText: 'Tax ID (EIN/VAT/ABN)',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          title: const Text('Show on invoices'),
          value: _showTaxId,
          onChanged: (v) => setState(() => _showTaxId = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _waLicense,
          decoration: const InputDecoration(
            labelText: 'WA Business License',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          title: const Text('Show on invoices'),
          value: _showWaLicense,
          onChanged: (v) => setState(() => _showWaLicense = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 3. Bank Details
// ─────────────────────────────────────────────────────────────────────

class _BankDetailsTile extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _BankDetailsTile({required this.profile});

  @override
  ConsumerState<_BankDetailsTile> createState() => _BankDetailsTileState();
}

class _BankDetailsTileState extends ConsumerState<_BankDetailsTile> {
  late final TextEditingController _bankName;
  late final TextEditingController _accountName;
  late final TextEditingController _accountNumber;
  late final TextEditingController _routingNumber;
  late final TextEditingController _swift;
  late final TextEditingController _iban;
  late String _accountType;
  late bool _showBankDetails;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _bankName = TextEditingController(text: p.bankName ?? '');
    _accountName = TextEditingController(text: p.bankAccountName ?? '');
    _accountNumber = TextEditingController(text: p.bankAccountNumber ?? '');
    _routingNumber = TextEditingController(text: p.bankRoutingNumber ?? '');
    _swift = TextEditingController(text: p.bankSwift ?? '');
    _iban = TextEditingController(text: p.bankIban ?? '');
    _accountType = p.bankAccountType;
    _showBankDetails = p.showBankDetails;
  }

  @override
  void dispose() {
    for (final c in [
      _bankName, _accountName, _accountNumber,
      _routingNumber, _swift, _iban,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    await ref.read(profileNotifierProvider.notifier).updateBankDetails(
          bankName: _t(_bankName),
          bankAccountName: _t(_accountName),
          bankAccountNumber: _t(_accountNumber),
          bankRoutingNumber: _t(_routingNumber),
          bankAccountType: _accountType,
          bankSwift: _t(_swift),
          bankIban: _t(_iban),
          showBankDetails: _showBankDetails,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bank details saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBank = widget.profile.bankName != null &&
        widget.profile.bankName!.isNotEmpty;

    return _ProfileExpansionCard(
      title: 'Bank Details',
      icon: Icons.account_balance_outlined,
      subtitle: hasBank
          ? '${widget.profile.bankName} · ****${_lastFour()}'
          : 'ACH, routing, SWIFT',
      isConfigured: hasBank,
      children: [
        const SizedBox(height: 8),
        TextFormField(
          controller: _bankName,
          decoration: const InputDecoration(
            labelText: 'Bank Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _accountName,
          decoration: const InputDecoration(
            labelText: 'Account Holder Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _routingNumber,
                decoration: const InputDecoration(
                  labelText: 'Routing Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _accountNumber,
                decoration: const InputDecoration(
                  labelText: 'Account Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _accountType,
          decoration: const InputDecoration(
            labelText: 'Account Type',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'checking', child: Text('Checking')),
            DropdownMenuItem(value: 'savings', child: Text('Savings')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _accountType = v);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _swift,
                decoration: const InputDecoration(
                  labelText: 'SWIFT Code',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _iban,
                decoration: const InputDecoration(
                  labelText: 'IBAN',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          title: const Text('Show on invoices'),
          value: _showBankDetails,
          onChanged: (v) => setState(() => _showBankDetails = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }

  String _lastFour() {
    final num = widget.profile.bankAccountNumber ?? '';
    if (num.length < 4) return num;
    return num.substring(num.length - 4);
  }
}

// ─────────────────────────────────────────────────────────────────────
// 4. Payment Links
// ─────────────────────────────────────────────────────────────────────

class _PaymentLinksTile extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _PaymentLinksTile({required this.profile});

  @override
  ConsumerState<_PaymentLinksTile> createState() => _PaymentLinksTileState();
}

class _PaymentLinksTileState extends ConsumerState<_PaymentLinksTile> {
  late final TextEditingController _stripeLink;
  late final TextEditingController _instructions;
  late bool _showStripeLink;

  @override
  void initState() {
    super.initState();
    _stripeLink =
        TextEditingController(text: widget.profile.stripePaymentLink ?? '');
    _instructions =
        TextEditingController(text: widget.profile.paymentInstructions ?? '');
    _showStripeLink = widget.profile.showStripeLink;
  }

  @override
  void dispose() {
    _stripeLink.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sl = _stripeLink.text.trim();
    final ins = _instructions.text.trim();
    await ref.read(profileNotifierProvider.notifier).updatePaymentLinks(
          stripePaymentLink: sl.isEmpty ? null : sl,
          showStripeLink: _showStripeLink,
          paymentInstructions: ins.isEmpty ? null : ins,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment links saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = widget.profile.stripePaymentLink != null &&
        widget.profile.stripePaymentLink!.isNotEmpty;

    return _ProfileExpansionCard(
      title: 'Payment Links',
      icon: Icons.link_outlined,
      subtitle: hasLink ? 'Stripe link configured' : 'Stripe, PayPal, Venmo, etc.',
      isConfigured: hasLink,
      children: [
        const SizedBox(height: 8),
        TextFormField(
          controller: _stripeLink,
          decoration: const InputDecoration(
            labelText: 'Stripe Payment Link',
            hintText: 'https://pay.stripe.com/...',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        SwitchListTile(
          title: const Text('Show on invoices'),
          value: _showStripeLink,
          onChanged: (v) => setState(() => _showStripeLink = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _instructions,
          decoration: const InputDecoration(
            labelText: 'Other Payment Instructions',
            hintText: 'PayPal, Venmo, Zelle, etc.',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 5. Defaults
// ─────────────────────────────────────────────────────────────────────

class _DefaultsTile extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _DefaultsTile({required this.profile});

  @override
  ConsumerState<_DefaultsTile> createState() => _DefaultsTileState();
}

class _DefaultsTileState extends ConsumerState<_DefaultsTile> {
  late final TextEditingController _currency;
  late final TextEditingController _hourlyRate;
  late final TextEditingController _taxLabel;
  late final TextEditingController _taxRate;
  late final TextEditingController _customDays;
  late final TextEditingController _lateFee;
  late PaymentTerms _paymentTerms;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _currency = TextEditingController(text: p.defaultCurrency);
    _hourlyRate = TextEditingController(text: p.defaultHourlyRate.toString());
    _taxLabel = TextEditingController(text: p.defaultTaxLabel);
    _taxRate = TextEditingController(text: p.defaultTaxRate.toString());
    _paymentTerms = PaymentTerms.fromString(p.defaultPaymentTerms);
    _customDays =
        TextEditingController(text: p.defaultPaymentTermsDays.toString());
    _lateFee = TextEditingController(
        text: p.lateFeePercentage?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _currency, _hourlyRate, _taxLabel, _taxRate, _customDays, _lateFee,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_hourlyRate.text) ?? 0.0;
    final taxR = double.tryParse(_taxRate.text) ?? 0.0;
    final days = int.tryParse(_customDays.text) ?? 30;
    final lf = _lateFee.text.trim().isEmpty
        ? null
        : double.tryParse(_lateFee.text);

    await ref.read(profileNotifierProvider.notifier).updateDefaults(
          defaultCurrency: _currency.text.trim().toUpperCase(),
          defaultHourlyRate: rate,
          defaultTaxLabel: _taxLabel.text.trim(),
          defaultTaxRate: taxR,
          defaultPaymentTerms: _paymentTerms.value,
          defaultPaymentTermsDays:
              _paymentTerms.resolveDays(customDays: days),
          lateFeePercentage: lf,
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Defaults saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final rateStr = p.defaultHourlyRate > 0
        ? '\$${p.defaultHourlyRate.toStringAsFixed(0)}/hr'
        : 'Not set';

    return _ProfileExpansionCard(
      title: 'Defaults',
      icon: Icons.tune_outlined,
      subtitle: '$rateStr · ${p.defaultCurrency} · ${_paymentTerms.label}',
      isConfigured: p.defaultHourlyRate > 0,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _hourlyRate,
                decoration: const InputDecoration(
                  labelText: 'Hourly Rate',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _taxLabel,
                decoration: const InputDecoration(
                  labelText: 'Tax Label',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _taxRate,
                decoration: const InputDecoration(
                  labelText: 'Tax Rate %',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PaymentTerms>(
          initialValue: _paymentTerms,
          decoration: const InputDecoration(
            labelText: 'Payment Terms',
            border: OutlineInputBorder(),
          ),
          items: PaymentTerms.values
              .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _paymentTerms = v);
          },
        ),
        if (_paymentTerms == PaymentTerms.custom) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _customDays,
            decoration: const InputDecoration(
              labelText: 'Custom Days',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _lateFee,
          decoration: const InputDecoration(
            labelText: 'Late Fee % (optional)',
            hintText: 'e.g. 1.5',
            border: OutlineInputBorder(),
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 6. Invoice Settings
// ─────────────────────────────────────────────────────────────────────

class _InvoiceSettingsTile extends ConsumerStatefulWidget {
  final UserProfile profile;
  const _InvoiceSettingsTile({required this.profile});

  @override
  ConsumerState<_InvoiceSettingsTile> createState() =>
      _InvoiceSettingsTileState();
}

class _InvoiceSettingsTileState extends ConsumerState<_InvoiceSettingsTile> {
  late final TextEditingController _prefix;
  late final TextEditingController _counter;
  late final TextEditingController _emailSubject;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _prefix = TextEditingController(text: widget.profile.invoiceNumberPrefix);
    _counter = TextEditingController(
        text: widget.profile.nextInvoiceNumber.toString());
    _emailSubject = TextEditingController(
        text: widget.profile.defaultEmailSubjectFormat);
    _selectedTemplateId = widget.profile.defaultTemplateId;
  }

  @override
  void dispose() {
    _prefix.dispose();
    _counter.dispose();
    _emailSubject.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final counterVal = int.tryParse(_counter.text.trim());
    if (counterVal == null || counterVal < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Next invoice number must be >= 1')));
      return;
    }
    await ref.read(profileNotifierProvider.notifier).updateInvoiceSettings(
          invoiceNumberPrefix: _prefix.text.trim(),
          defaultEmailSubjectFormat: _emailSubject.text.trim(),
          defaultTemplateId: _selectedTemplateId,
          nextInvoiceNumber: counterVal,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(allTemplatesProvider);
    final preview =
        '${_prefix.text}${(int.tryParse(_counter.text) ?? 1).toString().padLeft(4, '0')}';

    return _ProfileExpansionCard(
      title: 'Invoice Settings',
      icon: Icons.description_outlined,
      subtitle: 'Next: ${widget.profile.invoiceNumberPrefix}${widget.profile.nextInvoiceNumber.toString().padLeft(4, '0')}',
      isConfigured: true,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _prefix,
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _counter,
                decoration: InputDecoration(
                  labelText: 'Next Number',
                  helperText: preview,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailSubject,
          decoration: const InputDecoration(
            labelText: 'Email Subject Format',
            hintText: 'Invoice #{number} - {period}',
            border: OutlineInputBorder(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text('Tokens: {number}, {period}, {client}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        templatesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const SizedBox.shrink(),
          data: (templates) => DropdownButtonFormField<String?>(
            initialValue: _selectedTemplateId,
            decoration: const InputDecoration(
              labelText: 'Default Template',
              border: OutlineInputBorder(),
            ),
            items: templates
                .map((t) => DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(t.name),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedTemplateId = v),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 7. Backup Encryption
// ─────────────────────────────────────────────────────────────────────

class _BackupTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BackupTile> createState() => _BackupTileState();
}

class _BackupTileState extends ConsumerState<_BackupTile> {
  final _ctrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loaded = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pass = _ctrl.text.trim();
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passphrase cannot be empty')));
      return;
    }
    if (pass != _confirmCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passphrases do not match')));
      return;
    }
    await ref.read(appSettingsDaoProvider).setValue(_passphraseKey, pass);
    ref.invalidate(backupPassphraseProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup passphrase saved')));
    }
  }

  Future<void> _clear() async {
    await ref.read(appSettingsDaoProvider).deleteKey(_passphraseKey);
    ref.invalidate(backupPassphraseProvider);
    _ctrl.clear();
    _confirmCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup passphrase removed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final passphraseAsync = ref.watch(backupPassphraseProvider);

    return passphraseAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (stored) {
        if (!_loaded) {
          _loaded = true;
          if (stored != null) {
            _ctrl.text = stored;
            _confirmCtrl.text = stored;
          }
        }
        final hasStored = stored != null && stored.isNotEmpty;

        return _ProfileExpansionCard(
          title: 'Backup Encryption',
          icon: Icons.lock_outline,
          subtitle: hasStored ? 'Passphrase is set' : 'Set a backup passphrase',
          isConfigured: hasStored,
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm Passphrase',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (hasStored)
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Remove'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
