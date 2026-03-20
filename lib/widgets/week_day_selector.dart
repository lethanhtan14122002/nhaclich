import 'package:flutter/material.dart';

class WeekDaySelector extends StatefulWidget {
  final List<bool> selectedDays;
  final Function(List<bool>) onDaysSelected;
  final bool isRepeating;
  final Function(bool) onRepeatToggled;

  const WeekDaySelector({
    Key? key,
    required this.selectedDays,
    required this.onDaysSelected,
    required this.isRepeating,
    required this.onRepeatToggled,
  }) : super(key: key);

  @override
  State<WeekDaySelector> createState() => _WeekDaySelectorState();
}

class _WeekDaySelectorState extends State<WeekDaySelector> {
  late List<bool> _selectedDays;
  late bool _isRepeating;

  @override
  void initState() {
    super.initState();
    _selectedDays = List.from(widget.selectedDays);
    _isRepeating = widget.isRepeating;

    // If toggling on repeating and no days are selected, select at least Monday
    if (_isRepeating && !_selectedDays.contains(true)) {
      _selectedDays[0] = true;
      widget.onDaysSelected(_selectedDays);
    }
  }

  void _toggleDay(int index) {
    if (!_isRepeating) return;

    setState(() {
      _selectedDays[index] = !_selectedDays[index];

      // Make sure at least one day is selected
      if (!_selectedDays.contains(true)) {
        _selectedDays[index] =
            true; // Toggle back on if trying to unselect the last one
      }
    });
    widget.onDaysSelected(_selectedDays);
  }

  void _toggleRepeat(bool value) {
    setState(() {
      _isRepeating = value;

      // If turning on repeating, select at least Monday by default
      if (value && !_selectedDays.contains(true)) {
        _selectedDays[0] = true;
      }
    });
    widget.onRepeatToggled(value);
    widget.onDaysSelected(_selectedDays);
  }

  void _selectAllDays() {
    if (!_isRepeating) return;

    setState(() {
      _selectedDays = List.filled(7, true);
    });
    widget.onDaysSelected(_selectedDays);
  }

  void _selectWeekdays() {
    if (!_isRepeating) return;

    setState(() {
      _selectedDays = [true, true, true, true, true, false, false];
    });
    widget.onDaysSelected(_selectedDays);
  }

  void _selectWeekends() {
    if (!_isRepeating) return;

    setState(() {
      _selectedDays = [false, false, false, false, false, true, true];
    });
    widget.onDaysSelected(_selectedDays);
  }

  @override
  Widget build(BuildContext context) {
    const List<String> dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Repeat toggle
            SwitchListTile(
              title: const Text(
                'Lặp lại báo thức',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              value: _isRepeating,
              onChanged: _toggleRepeat,
              activeColor: Colors.blue,
            ),

            // Quick selection buttons (only visible if repeating is enabled)
            if (_isRepeating) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: _selectAllDays,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.1),
                        foregroundColor: Colors.blue,
                      ),
                      child: const Text('Hàng ngày'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectWeekends,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.1),
                        foregroundColor: Colors.blue,
                      ),
                      child: const Text('Cuối tuần'),
                    ),
                  ],
                ),
              ),
            ],

            // Day selection circles (only visible if repeating is enabled)
            if (_isRepeating) ...[
              const SizedBox(height: 11),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (index) {
                  return GestureDetector(
                    onTap: () => _toggleDay(index),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: _selectedDays[index]
                          ? Colors.blue
                          : Colors.grey.shade200,
                      child: Text(
                        dayNames[index],
                        style: TextStyle(
                          color: _selectedDays[index]
                              ? Colors.white
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
