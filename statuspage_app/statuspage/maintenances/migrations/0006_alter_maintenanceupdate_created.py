# Generated by Django 4.1.7 on 2023-03-10 14:08

from django.db import migrations, models
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ('maintenances', '0005_alter_maintenance_created'),
    ]

    operations = [
        migrations.AlterField(
            model_name='maintenanceupdate',
            name='created',
            field=models.DateTimeField(default=django.utils.timezone.now),
        ),
    ]
