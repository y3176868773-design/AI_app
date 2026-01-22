# Environment Variables Setup

This project uses environment variables to manage sensitive data like API keys.

## Setup Instructions

1. Copy the `.env.example` file to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Edit the `.env` file with your actual API keys:
   ```
   GEMINI_API_KEY=your_actual_api_key_here
   ```

## Security Notes

- The `.env` file is already included in `.gitignore` to prevent accidental commits
- Never commit your actual API keys to version control
- The `.env.example` file serves as a template with placeholder values

## Adding New Environment Variables

1. Add your variable to `.env`:
   ```
   NEW_VARIABLE=your_value_here
   ```

2. Access it in your Dart code:
   ```dart
   import 'package:flutter_dotenv/flutter_dotenv.dart';
   
   // Load the .env file (usually in main.dart)
   await dotenv.load(fileName: ".env");
   
   // Access the variable
   final value = dotenv.env['NEW_VARIABLE'] ?? '';
   ```