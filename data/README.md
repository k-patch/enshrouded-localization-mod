# Localization Mod - Translation Files

## File Naming Convention

Place your translation CSV files in this directory following this pattern:

```
{language_code}.csv
```

### CSV Format

```csv
0x12345678,Translated Text Here
0xabcdef00,Another Translation
```

- **Column 1**: Localization ID in hexadecimal format (0x prefix)
- **Column 2**: Translated text (use `\n` for newlines, which will be automatically converted)

### Example Files

- `ko_kr.csv` - Korean
- `ja_jp.csv` - Japanese
- `zh_cn.csv` - Chinese
- `de_de.csv` - German
- `fr_fr.csv` - French
- `others.csv` - Other languages

### How It Works

1. The mod automatically scans this directory for files matching `*.csv`
2. Extracts the language code from the filename
3. Applies the translations to the corresponding language entry in the game
4. Multiple language files can be present - all will be processed

### Notes

- You can have multiple translation files for different languages
- Only existing language entries in the game can be modified
- Newlines in translations: use `\n` in the CSV (will be converted to actual newlines)

