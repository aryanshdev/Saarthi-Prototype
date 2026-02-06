import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactDetailsScreen extends StatefulWidget {
  const ContactDetailsScreen({super.key});

  @override
  State<ContactDetailsScreen> createState() => _ContactDetailsScreenState();
}

class _ContactDetailsScreenState extends State<ContactDetailsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bloodGroupController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emergencyContactController = TextEditingController();
  final TextEditingController _emergencyAddressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameController.text = prefs.getString('name') ?? '';
        _bloodGroupController.text = prefs.getString('bloodGroup') ?? '';
        _addressController.text = prefs.getString('address') ?? '';
        _emergencyContactController.text = prefs.getString('emergencyContact') ?? '';
        _emergencyAddressController.text = prefs.getString('emergencyAddress') ?? '';
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', _nameController.text);
    await prefs.setString('bloodGroup', _bloodGroupController.text);
    await prefs.setString('address', _addressController.text);
    await prefs.setString('emergencyContact', _emergencyContactController.text);
    await prefs.setString('emergencyAddress', _emergencyAddressController.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Emergency Protocol Updated Successfully'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bloodGroupController.dispose();
    _addressController.dispose();
    _emergencyContactController.dispose();
    _emergencyAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'EMERGENCY INFO',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.red.shade50.withOpacity(0.5)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 32),
              _buildSectionHeader('MEDICAL & PERSONAL', Icons.health_and_safety_rounded),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _nameController,
                label: 'FULL NAME',
                hint: 'Enter your legal name',
                icon: Icons.person_rounded,
                color: Colors.blue.shade600,
              ),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _bloodGroupController,
                label: 'BLOOD GROUP',
                hint: 'e.g. B+ Positive',
                icon: Icons.bloodtype_rounded,
                color: Colors.red.shade600,
              ),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _addressController,
                label: 'RESIDENTIAL ADDRESS',
                hint: 'Your home location',
                icon: Icons.home_rounded,
                maxLines: 2,
                color: Colors.indigo.shade600,
              ),
              const SizedBox(height: 32),
              _buildSectionHeader('EMERGENCY CONTACTS', Icons.contact_emergency_rounded),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _emergencyContactController,
                label: 'EMERGENCY CONTACT',
                hint: 'Name and Phone number',
                icon: Icons.phone_rounded,
                color: Colors.orange.shade700,
              ),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _emergencyAddressController,
                label: 'EMERGENCY ADDRESS',
                hint: 'Contact\'s location',
                icon: Icons.location_on_rounded,
                maxLines: 2,
                color: Colors.orange.shade700,
              ),
              const SizedBox(height: 48),
              _buildActionButtons(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.shield_rounded, size: 32, color: Colors.red.shade700),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Life-Saving Data',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Text(
                  'Crucial info for responders during a crisis.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.red.shade800),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.red.shade800, letterSpacing: 1.1),
        ),
      ],
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: color, size: 22),
          labelStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500, fontSize: 12),
          hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 14),
          floatingLabelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [Colors.red.shade600, Colors.red.shade800]),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _saveData,
          borderRadius: BorderRadius.circular(20),
          child: const SizedBox(
            height: 64,
            width: double.infinity,
            child: Center(
              child: Text(
                'Save Data',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
