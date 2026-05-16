import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const locations = await db.location.findMany({
      include: {
        device: {
          include: {
            member: true,
          },
        },
      },
      orderBy: { timestamp: 'desc' },
    });

    return NextResponse.json(locations);
  } catch (error) {
    console.error('Locations GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch location data' }, { status: 500 });
  }
}
