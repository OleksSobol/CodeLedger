import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/database/app_database.dart';
import '../../../../core/constants/payment_terms.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';
import '../providers/client_providers.dart';

class ClientFormPage extends ConsumerStatefulWidget {
  final Client? client;

  const ClientFormPage({super.key, this.client});

  @override
  ConsumerState<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends ConsumerState<ClientFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressLine1Ctrl;
  late final TextEditingController _addressLine2Ctrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _postalCodeCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _hourlyRateCtrl;
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _taxRateCtrl;
  late final TextEditingController _customDaysCtrl;
  late final TextEditingController _notesCtrl;
  PaymentTerms? _paymentTerms;
  bool _saving = false;

  bool get _isEditing => widget.client != null;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _contactNameCtrl = TextEditingController(text: c?.contactName ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _addressLine1Ctrl = TextEditingController(text: c?.addressLine1 ?? '');
    _addressLine2Ctrl = TextEditingController(text: c?.addressLine2 ?? '');
    _cityCtrl = TextEditingController(text: c?.city ?? '');
    _stateCtrl = TextEditingController(text: c?.stateProvince ?? '');
    _postalCodeCtrl = TextEditingController(text: c?.postalCode ?? '');
    _countryCtrl = TextEditingController(text: c?.country ?? '');
    _hourlyRateCtrl =
        TextEditingController(text: c?.hourlyRate?.toString() ?? '');
    _currencyCtrl = TextEditingController(text: c?.currency ?? 'USD');
    _taxRateCtrl =
        TextEditingController(text: c?.taxRate?.toString() ?? '');
    _paymentTerms = c?.paymentTermsOverride != null
        ? PaymentTerms.fromString(c!.paymentTermsOverride!)
        : null;
    _customDaysCtrl = TextEditingController(
        text: c?.paymentTermsDaysOverride?.toString() ?? '');
    _notesCtrl = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressLine1Ctrl.dispose();
    _addressLine2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postalCodeCtrl.dispose();
    _countryCtrl.dispose();
    _hourlyRateCtrl.dispose();
    _currencyCtrl.dispose();
    _taxRateCtrl.dispose();
    _customDaysCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final notifier = ref.read(clientNotifierProvider.notifier);
      final hourlyRate = double.tryParse(_hourlyRateCtrl.text);
      final taxRate = double.tryParse(_taxRateCtrl.text);
      final customDays = int.tryParse(_customDaysCtrl.text);

      if (_isEditing) {
        final oldRate = widget.client!.hourlyRate;
        final rateChanged = hourlyRate != null &&
            oldRate != null &&
            hourlyRate != oldRate;

        await notifier.updateClient(
          widget.client!.id,
          ClientsCompanion(
            name: Value(_nameCtrl.text.trim()),
            contactName: Value(_trimOrNull(_contactNameCtrl.text)),
            email: Value(_trimOrNull(_emailCtrl.text)),
            phone: Value(_trimOrNull(_phoneCtrl.text)),
            addressLine1: Value(_trimOrNull(_addressLine1Ctrl.text)),
            addressLine2: Value(_trimOrNull(_addressLine2Ctrl.text)),
            city: Value(_trimOrNull(_cityCtrl.text)),
            stateProvince: Value(_trimOrNull(_stateCtrl.text)),
            postalCode: Value(_trimOrNull(_postalCodeCtrl.text)),
            country: Value(_trimOrNull(_countryCtrl.text)),
            hourlyRate: Value(hourlyRate),
            currency: Value(_currencyCtrl.text.trim().toUpperCase()),
            taxRate: Value(taxRate),
            paymentTermsOverride: Value(_paymentTerms?.value),
            paymentTermsDaysOverride: Value(
              _paymentTerms == PaymentTerms.custom ? customDays : null,
            ),
            notes: Value(_trimOrNull(_notesCtrl.text)),
          ),
        );

        // If rate changed, offer to update uninvoiced entries
        if (rateChanged && mounted) {
          final dao = ref.read(timeEntryRepositoryProvider);
          final count =
              await dao.countUninvoicedAtRate(widget.client!.id, oldRate);
          if (count > 0 && mounted) {
            final update = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Update Existing Entries?'),
                content: Text(
                  'You have $count uninvoiced entr${count == 1 ? 'y' : 'ies'} '
                  'recorded at ${formatCurrency(oldRate)}/hr.\n\n'
                  'Update ${count == 1 ? 'it' : 'them'} to '
                  '${formatCurrency(hourlyRate)}/hr?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep Old Rate'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Update'),
                  ),
                ],
              ),
            );
            if (update == true) {
              await dao.updateRateForClient(
                  widget.client!.id, hourlyRate);
              if (mounted) {
                ref.invalidate(filteredEntriesProvider);
              }
            }
          }
        }
      } else {
        await notifier.addClient(
          name: _nameCtrl.text.trim(),
          contactName: _trimOrNull(_contactNameCtrl.text),
          email: _trimOrNull(_emailCtrl.text),
          phone: _trimOrNull(_phoneCtrl.text),
          addressLine1: _trimOrNull(_addressLine1Ctrl.text),
          addressLine2: _trimOrNull(_addressLine2Ctrl.text),
          city: _trimOrNull(_cityCtrl.text),
          stateProvince: _trimOrNull(_stateCtrl.text),
          postalCode: _trimOrNull(_postalCodeCtrl.text),
          country: _trimOrNull(_countryCtrl.text),
          hourlyRate: hourlyRate,
          currency: _currencyCtrl.text.trim().toUpperCase(),
          taxRate: taxRate,
          paymentTermsOverride: _paymentTerms?.value,
          paymentTermsDaysOverride:
              _paymentTerms == PaymentTerms.custom ? customDays : null,
          notes: _trimOrNull(_notesCtrl.text),
        );
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Client' : 'Add Client'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Client Name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
              autofocus: !_isEditing,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactNameCtrl,
              decoration: const InputDecoration(labelText: 'Contact Name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            Text('Address',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressLine1Ctrl,
              decoration:
                  const InputDecoration(labelText: 'Address Line 1'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressLine2Ctrl,
              decoration:
                  const InputDecoration(labelText: 'Address Line 2'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cityCtrl,
                    decoration:
                        const InputDecoration(labelText: 'City'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _stateCtrl,
                    decoration:
                        const InputDecoration(labelText: 'State'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _postalCodeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Postal Code'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _countryCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Country'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Billing',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hourlyRateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Hourly Rate',
                      hintText: 'Uses default if empty',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _currencyCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Currency'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _taxRateCtrl,
              decoration: const InputDecoration(
                labelText: 'Tax Rate %',
                hintText: 'Uses default if empty',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentTerms?>(
              initialValue: _paymentTerms,
              decoration: const InputDecoration(
                labelText: 'Payment Terms Override',
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Use default')),
                ...PaymentTerms.values.map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label),
                    )),
              ],
              onChanged: (v) => setState(() => _paymentTerms = v),
            ),
            if (_paymentTerms == PaymentTerms.custom) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customDaysCtrl,
                decoration:
                    const InputDecoration(labelText: 'Custom Days'),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 24),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SafeArea(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Save Changes' : 'Add Client'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
