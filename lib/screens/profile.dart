import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _vehicleNameController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _ownerNumberController = TextEditingController();
  final TextEditingController _numberPlateController = TextEditingController();
  final TextEditingController _additionalInfoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _editPasswordController = TextEditingController();
  final TextEditingController _deletePhotoPasswordController = TextEditingController();
  final TextEditingController _deleteVehiclePasswordController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newConfirmPasswordController = TextEditingController();

  String? _ownerPhotoPath;
  bool _isSaved = false;
  bool _isEditingEnabled = false;
  bool _hasData = false;
  bool _isPasswordSet = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vehicleNameController.text = prefs.getString('vehicleName') ?? '';
      _vehicleModelController.text = prefs.getString('vehicleModel') ?? '';
      _ownerNumberController.text = prefs.getString('ownerNumber') ?? '';
      _numberPlateController.text = prefs.getString('numberPlate') ?? '';
      _additionalInfoController.text = prefs.getString('additionalInfo') ?? '';
      _ownerPhotoPath = prefs.getString('ownerPhotoPath');
      _isPasswordSet = prefs.getString('password') != null && prefs.getString('password')!.isNotEmpty;
      _hasData = _vehicleNameController.text.isNotEmpty ||
          _vehicleModelController.text.isNotEmpty ||
          _ownerNumberController.text.isNotEmpty ||
          _numberPlateController.text.isNotEmpty ||
          _additionalInfoController.text.isNotEmpty;
      _isSaved = _hasData;
      _isEditingEnabled = !_isSaved;
    });
    print('Loaded data from SharedPreferences at ${DateTime.now()}');
  }

  Future<void> _saveVehicleInfo() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vehicleName', _vehicleNameController.text);
      await prefs.setString('vehicleModel', _vehicleModelController.text);
      await prefs.setString('ownerNumber', _ownerNumberController.text);
      await prefs.setString('numberPlate', _numberPlateController.text);
      await prefs.setString('additionalInfo', _additionalInfoController.text);
      setState(() {
        _isSaved = true;
        _isEditingEnabled = false;
        _hasData = true;
      });
      print('Saved vehicle info to SharedPreferences at ${DateTime.now()}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle information saved successfully!')),
      );
    }
  }

  Future<void> _setPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPassword = prefs.getString('password');

    if (_isPasswordSet && savedPassword != null) {
      // Password exists, prompt for existing password to change it
      bool? passwordCorrect;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Change Password'),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _currentPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Enter your current password',
                        errorText: passwordCorrect == false ? 'Incorrect password' : null,
                      ),
                      obscureText: true,
                      onChanged: (value) {
                        if (passwordCorrect == false) {
                          setDialogState(() {
                            passwordCorrect = null;
                          });
                        }
                      },
                    ),
                    if (passwordCorrect == true) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'New Password',
                          hintText: 'Enter new password',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newConfirmPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Confirm New Password',
                          hintText: 'Confirm new password',
                        ),
                        obscureText: true,
                      ),
                    ],
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _currentPasswordController.clear();
                  _newPasswordController.clear();
                  _newConfirmPasswordController.clear();
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (passwordCorrect != true) {
                    // Verify current password
                    if (_currentPasswordController.text != savedPassword) {
                      setState(() {
                        passwordCorrect = false;
                      });
                      return;
                    }
                    setState(() {
                      passwordCorrect = true;
                    });
                  } else {
                    // Set new password
                    if (_newPasswordController.text.isEmpty || _newConfirmPasswordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter both new password and confirmation password')),
                      );
                      return;
                    }

                    if (_newPasswordController.text != _newConfirmPasswordController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('New passwords do not match!')),
                      );
                      return;
                    }

                    await prefs.setString('password', _newPasswordController.text);
                    setState(() {
                      _isPasswordSet = true;
                    });
                    Navigator.of(context).pop();
                    _currentPasswordController.clear();
                    _newPasswordController.clear();
                    _newConfirmPasswordController.clear();
                    print('Password changed successfully at ${DateTime.now()}');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password changed successfully!')),
                    );
                  }
                },
                child: Text(passwordCorrect == true ? 'Change' : 'Verify'),
              ),
            ],
          );
        },
      );
    } else {
      // No password set, allow setting a new password
      if (_passwordController.text.isEmpty || _confirmPasswordController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter both password and confirmation password')),
        );
        return;
      }

      if (_passwordController.text != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwords do not match!')),
        );
        return;
      }

      await prefs.setString('password', _passwordController.text);
      setState(() {
        _isPasswordSet = true;
      });
      print('Password set successfully at ${DateTime.now()}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password set successfully!')),
      );
    }
  }

  Future<void> _deleteVehicleInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPassword = prefs.getString('password');
    if (savedPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a password first!')),
      );
      Navigator.of(context).pop();
      return;
    }

    if (_deleteVehiclePasswordController.text != savedPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect password!')),
      );
      return;
    }

    await prefs.remove('vehicleName');
    await prefs.remove('vehicleModel');
    await prefs.remove('ownerNumber');
    await prefs.remove('numberPlate');
    await prefs.remove('additionalInfo');
    setState(() {
      _vehicleNameController.clear();
      _vehicleModelController.clear();
      _ownerNumberController.clear();
      _numberPlateController.clear();
      _additionalInfoController.clear();
      _isSaved = false;
      _isEditingEnabled = true;
      _hasData = false;
    });
    Navigator.of(context).pop();
    _deleteVehiclePasswordController.clear();
    print('Deleted vehicle info from SharedPreferences at ${DateTime.now()}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vehicle information deleted!')),
    );
  }

  Future<void> _pickOwnerPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ownerPhotoPath', pickedFile.path);
      setState(() {
        _ownerPhotoPath = pickedFile.path;
      });
      print('Owner photo set at ${DateTime.now()}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner photo updated!')),
      );
    }
  }

  Future<void> _deleteOwnerPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPassword = prefs.getString('password');
    if (savedPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a password first!')),
      );
      return;
    }

    if (_deletePhotoPasswordController.text != savedPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect password!')),
      );
      return;
    }

    await prefs.remove('ownerPhotoPath');
    setState(() {
      _ownerPhotoPath = null;
      _deletePhotoPasswordController.clear();
    });
    Navigator.of(context).pop();
    print('Owner photo deleted at ${DateTime.now()}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Owner photo deleted!')),
    );
  }

  void _showEditPasswordDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Password to Edit'),
          content: TextFormField(
            controller: _editPasswordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your password to edit fields',
            ),
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _editPasswordController.clear();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final savedPassword = prefs.getString('password');
                if (savedPassword == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please set a password first!')),
                  );
                  Navigator.of(context).pop();
                  return;
                }

                if (_editPasswordController.text != savedPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Incorrect password!')),
                  );
                  return;
                }

                setState(() {
                  _isEditingEnabled = true;
                  _isSaved = false;
                });
                Navigator.of(context).pop();
                _editPasswordController.clear();
                print('Editing enabled at ${DateTime.now()}');
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteVehicleDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Vehicle Info'),
          content: TextFormField(
            controller: _deleteVehiclePasswordController,
            decoration: const InputDecoration(
              labelText: 'Enter Password',
              hintText: 'Enter your password to delete vehicle info',
            ),
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteVehiclePasswordController.clear();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _deleteVehicleInfo,
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePhotoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Owner Photo'),
          content: TextFormField(
            controller: _deletePhotoPasswordController,
            decoration: const InputDecoration(
              labelText: 'Enter Password',
              hintText: 'Enter your password to delete the photo',
            ),
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deletePhotoPasswordController.clear();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _deleteOwnerPhoto,
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _vehicleNameController.dispose();
    _vehicleModelController.dispose();
    _ownerNumberController.dispose();
    _numberPlateController.dispose();
    _additionalInfoController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _editPasswordController.dispose();
    _deletePhotoPasswordController.dispose();
    _deleteVehiclePasswordController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _newConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Profile'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _ownerPhotoPath != null ? FileImage(File(_ownerPhotoPath!)) : null,
                      child: _ownerPhotoPath == null
                          ? Icon(
                        Icons.person,
                        size: 50,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickOwnerPhoto,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Theme.of(context).colorScheme.onSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if (_ownerPhotoPath != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: GestureDetector(
                          onTap: _showDeletePhotoDialog,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Enter Vehicle Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _vehicleNameController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Name',
                        hintText: 'e.g., Yamaha R15',
                      ),
                      enabled: _isEditingEnabled,
                      onTap: _isSaved && !_isEditingEnabled ? _showEditPasswordDialog : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the vehicle name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _vehicleModelController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Model',
                        hintText: 'e.g., 2023 Model',
                      ),
                      enabled: _isEditingEnabled,
                      onTap: _isSaved && !_isEditingEnabled ? _showEditPasswordDialog : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the vehicle model';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ownerNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Owner Phone Number',
                        hintText: 'e.g., 9876543210',
                        counterText: '',
                      ),
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      enabled: _isEditingEnabled,
                      onTap: _isSaved && !_isEditingEnabled ? _showEditPasswordDialog : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the owner\'s phone number';
                        }
                        if (value.length != 10) {
                          return 'Phone number must be exactly 10 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _numberPlateController,
                      decoration: const InputDecoration(
                        labelText: 'Number Plate',
                        hintText: 'e.g., KA 01 AB 1234',
                      ),
                      enabled: _isEditingEnabled,
                      onTap: _isSaved && !_isEditingEnabled ? _showEditPasswordDialog : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the number plate';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _additionalInfoController,
                      decoration: const InputDecoration(
                        labelText: 'Additional Info',
                        hintText: 'e.g., Color: Blue, Last Serviced: 2025-01-15',
                      ),
                      maxLines: 3,
                      enabled: _isEditingEnabled,
                      onTap: _isSaved && !_isEditingEnabled ? _showEditPasswordDialog : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter additional information';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isEditingEnabled ? _saveVehicleInfo : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_hasData)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _showDeleteVehicleDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isPasswordSet ? 'Change Password' : 'Set Password',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              if (!_isPasswordSet) ...[
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter password for editing/deleting',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Confirm password for editing/deleting',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _setPassword,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isPasswordSet ? 'Change Password' : 'Set Password',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}